import 'dart:async';
import 'dart:math';
import 'dart:ui' show FlutterView;

import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../l10n/app_localizations.dart';
import '../models/place.dart';
import '../providers/services.dart';
import '../providers/saved_places.dart';

/// One field of the route: shows the chosen place, and searches while typing.
class SearchField extends ConsumerStatefulWidget {
  const SearchField({
    super.key,
    required this.label,
    required this.place,
    required this.onChosen,
    required this.onCleared,
    this.near,
    this.icon = Icons.place_outlined,
    this.floating = false,
    this.before,
    this.myLocation,
  });

  final String label;
  final Place? place;
  final ValueChanged<Place> onChosen;
  final VoidCallback onCleared;

  /// The center of the map: results near it come first.
  final LatLng? Function()? near;
  final IconData icon;

  /// The search bar of the search screen: without border and label, the
  /// suggestions in the same card below it.
  final bool floating;

  /// Before the text field, for example the drag handle of the route list.
  final Widget? before;

  /// Provides your own location (and asks for permission if needed). Null if
  /// that failed; the caller has then already said why. Without this function
  /// "My location" is not among the suggestions.
  final Future<Place?> Function()? myLocation;

  @override
  ConsumerState<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends ConsumerState<SearchField>
    with WidgetsBindingObserver {
  final _text = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  Timer? _close;
  CancelToken? _inFlight;
  List<Place> _results = const [];

  /// A search is under way (typed, not answered yet).
  bool _searching = false;

  /// How the last search ended, if not with results: the text nothing was
  /// found for, or that it failed. So "still searching", "nothing there" and
  /// "the server is down" don't all look like an empty list.
  String? _nothingFor;
  bool _failed = false;

  /// Enter was pressed before the results were in: the first one is chosen
  /// as soon as they are.
  bool _submitted = false;

  /// The suggestion the arrow keys are on (-1: none), and what picking each
  /// of the suggestions shown does.
  int _highlight = -1;
  List<VoidCallback> _choices = const [];

  /// The suggestions are open: the field has focus, or just had it (see the
  /// focus listener).
  bool _open = false;

  /// What the field should show when nobody is typing. A field of its own and
  /// not `widget.place`: when choosing, the field loses focus before the
  /// planner has returned the new place, and then the choice would be wiped
  /// out right away.
  String _label = '';

  /// The on-screen keyboard was up while the field had focus.
  bool _keyboardUp = false;
  FlutterView? _view;

  String _display(Place? place) =>
      place?.display(AppLocalizations.of(context)) ?? '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _focus.addListener(() {
      if (_focus.hasFocus) {
        _close?.cancel();
        setState(() => _open = true);
        return;
      }
      // Left without choosing: back to what was there. Only a moment later --
      // in some browsers a click on a suggestion first removes the focus, and
      // then the list was gone before the click arrived. Also the text: the
      // suggestions depend on it, and putting the label back right away swapped
      // the search results for the recent places under the click.
      _close?.cancel();
      _close = Timer(const Duration(milliseconds: 250), () {
        if (mounted && !_focus.hasFocus) {
          _text.text = _label;
          _debounce?.cancel();
          _inFlight?.cancel();
          setState(() {
            _results = const [];
            _clearOutcome();
            _open = false;
          });
        }
      });
    });
  }

  void _clearOutcome() {
    _highlight = -1;
    _searching = false;
    _nothingFor = null;
    _failed = false;
    _submitted = false;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _view = View.of(context);
    // Here and not in initState: the name of "My location" comes from the
    // translation, and that can't be read in initState yet.
    _label = _display(widget.place);
    if (!_focus.hasFocus) _text.text = _label;
  }

  @override
  void didUpdateWidget(SearchField old) {
    super.didUpdateWidget(old);
    if (old.place != widget.place) {
      _label = _display(widget.place);
      if (!_focus.hasFocus) _text.text = _label;
    }
  }

  /// Back on Android first closes the keyboard, and Flutter never hears of
  /// it; then the suggestions stayed, and the next back left the app. A
  /// keyboard that goes away is taken as done searching.
  @override
  void didChangeMetrics() {
    final view = _view;
    if (!mounted || view == null) return;
    final up = view.viewInsets.bottom > 0;
    if (_keyboardUp && !up && _focus.hasFocus) _focus.unfocus();
    _keyboardUp = up && _focus.hasFocus;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounce?.cancel();
    _close?.cancel();
    _inFlight?.cancel();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _typed(String text) {
    // "My location" depends on what has been typed.
    setState(() {
      _clearOutcome();
      _searching = text.trim().length >= 2;
    });
    _debounce?.cancel();
    // Not a request on every key: only after a short pause.
    _debounce = Timer(const Duration(milliseconds: 250), () => _find(text));
  }

  Future<void> _find(String text) async {
    _inFlight?.cancel();
    final photon = ref.read(photonProvider);
    if (photon == null) {
      setState(() => _searching = false);
      return;
    }
    final cancel = _inFlight = CancelToken();
    try {
      final found = await photon.search(
        text,
        near: widget.near?.call(),
        cancel: cancel,
      );
      if (!mounted || cancel.isCancelled) return;
      if (_submitted && found.isNotEmpty) {
        _choose(found.first, remember: true);
        return;
      }
      setState(() {
        _results = found;
        _highlight = -1;
        _searching = false;
        _submitted = false;
        _nothingFor = found.isEmpty && text.trim().length >= 2
            ? text.trim()
            : null;
      });
    } catch (_) {
      // No connection, or an answer that isn't one. Not a dialog: a line in
      // the list, where the results would have been.
      if (mounted && !cancel.isCancelled) {
        setState(() {
          _results = const [];
          _searching = false;
          _submitted = false;
          _failed = true;
        });
      }
    }
  }

  /// [remember]: a search result or recent place goes (back) to the front of
  /// the recent ones; home, work and "My location" don't.
  void _choose(Place place, {bool remember = false}) {
    if (remember) ref.read(savedPlacesProvider.notifier).remember(place);
    _close?.cancel();
    _text.text = _label = _display(place);
    _debounce?.cancel();
    _inFlight?.cancel();
    setState(() {
      _results = const [];
      _clearOutcome();
      _open = false;
    });
    widget.onChosen(place);
    _focus.unfocus();
  }

  Future<void> _chooseMyLocation() async {
    final place = await widget.myLocation!();
    if (place != null && mounted) _choose(place);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    // On top as long as nothing or the start of "My location" is typed.
    final typed = _text.text.trim().toLowerCase();
    final withMyLocation =
        widget.myLocation != null &&
        _open &&
        (typed.isEmpty ||
            typed == _label.toLowerCase() ||
            l.myLocation.toLowerCase().startsWith(typed));
    // Home and work if the field is empty or you start typing their name; the
    // recent ones if it is empty, or those that contain what was typed.
    final savedPlaces = ref.watch(savedPlacesProvider);
    final empty = typed.isEmpty || typed == _label.toLowerCase();
    final fixed = !_open
        ? const <(IconData, String, Place)>[]
        : [
            for (final (icon, label, place) in [
              (Icons.home_outlined, l.home, savedPlaces.home),
              (Icons.work_outline, l.work, savedPlaces.work),
            ])
              if (place != null &&
                  (empty || label.toLowerCase().startsWith(typed)))
                (icon, label, place),
          ];
    final recent = !_open
        ? const <Place>[]
        : empty
        ? savedPlaces.recent.take(5).toList()
        : savedPlaces.recent
              .where((p) => p.label.toLowerCase().contains(typed))
              .take(3)
              .toList();
    final nothing = _open && !_searching ? _nothingFor : null;
    final failed = _open && !_searching && _failed;
    final suggestions =
        _results.isNotEmpty ||
        withMyLocation ||
        fixed.isNotEmpty ||
        recent.isNotEmpty ||
        nothing != null ||
        failed;
    final field = TextField(
      controller: _text,
      focusNode: _focus,
      onChanged: _typed,
      onSubmitted: (text) {
        if (_highlight >= 0 && _highlight < _choices.length) {
          _choices[_highlight]();
        } else if (_results.isNotEmpty) {
          _choose(_results.first, remember: true);
        } else if (text.trim().length >= 2) {
          // Enter before the results are in (or after a failure): search now
          // and take the first.
          _debounce?.cancel();
          setState(() {
            _clearOutcome();
            _searching = true;
            _submitted = true;
          });
          _find(text);
        }
      },
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        labelText: widget.floating ? null : widget.label,
        hintText: widget.floating ? widget.label : l.searchPlace,
        prefixIcon: Icon(widget.icon),
        isDense: true,
        border: widget.floating ? InputBorder.none : const OutlineInputBorder(),
        contentPadding: widget.floating
            ? const EdgeInsets.symmetric(vertical: 14)
            : null,
        suffixIcon: widget.place == null && _text.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.clear),
                tooltip: l.removeLabel,
                onPressed: () {
                  _text.clear();
                  _label = '';
                  _debounce?.cancel();
                  _inFlight?.cancel();
                  setState(() {
                    _results = const [];
                    _clearOutcome();
                  });
                  widget.onCleared();
                },
              ),
      ),
    );
    // What the arrow keys walk through and Enter picks: every suggestion, in
    // the order it is shown.
    final choices = <VoidCallback>[];
    Widget choice({
      Key? key,
      required Widget leading,
      required Widget title,
      Widget? subtitle,
      required VoidCallback onTap,
    }) {
      final index = choices.length;
      choices.add(onTap);
      return ListTile(
        key: key,
        dense: true,
        selected: index == _highlight,
        selectedTileColor: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest,
        leading: leading,
        title: title,
        subtitle: subtitle,
        onTap: onTap,
      );
    }

    final tiles = [
      if (withMyLocation)
        choice(
          leading: Icon(
            Icons.my_location,
            color: Theme.of(context).colorScheme.primary,
          ),
          title: Text(l.myLocation),
          onTap: _chooseMyLocation,
        ),
      for (final (icon, label, place) in fixed)
        choice(
          key: ValueKey('fixed:$label'),
          leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
          title: Text(label),
          subtitle: Text(
            [
              place.label,
              place.description,
            ].where((t) => t.isNotEmpty).join(', '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => _choose(
            Place(label: label, description: place.label, point: place.point),
          ),
        ),
      for (final place in recent)
        choice(
          key: ValueKey('recent:${place.label}:${place.point}'),
          leading: const Icon(Icons.history),
          title: Text(
            place.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: place.description.isEmpty
              ? null
              : Text(
                  place.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
          onTap: () => _choose(place, remember: true),
        ),
      for (final place in _results)
        choice(
          key: ValueKey('result:${place.label}:${place.point}'),
          leading: const Icon(Icons.place_outlined),
          title: Text(
            _display(place),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: place.description.isEmpty
              ? null
              : Text(
                  place.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
          onTap: () => _choose(place, remember: true),
        ),
      if (nothing != null)
        ListTile(
          dense: true,
          leading: const Icon(Icons.search_off),
          title: Text(l.searchNoResults(nothing)),
        ),
      if (failed)
        ListTile(
          dense: true,
          leading: Icon(
            Icons.cloud_off,
            color: Theme.of(context).colorScheme.error,
          ),
          title: Text(l.searchFailed),
          onTap: () {
            setState(() {
              _clearOutcome();
              _searching = true;
            });
            _find(_text.text);
          },
        ),
    ];
    _choices = choices;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // With a keyboard: the arrows walk through the suggestions, Enter
        // takes the one that is lit, Escape leaves the field.
        CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): _focus.unfocus,
            const SingleActivator(LogicalKeyboardKey.arrowDown): () => setState(
              () => _highlight = min(_highlight + 1, _choices.length - 1),
            ),
            const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                setState(() => _highlight = max(_highlight - 1, -1)),
          },
          child: widget.before == null
              ? field
              : Row(
                  children: [
                    widget.before!,
                    Expanded(child: field),
                  ],
                ),
        ),
        if (_open && _searching)
          const LinearProgressIndicator(minHeight: 2)
        else if (widget.floating && suggestions)
          const Divider(height: 1),
        // The floating bar lies over the map and has the height that's left
        // above the keyboard: more suggestions than fit there scroll. In the
        // route panel the panel itself scrolls.
        if (widget.floating)
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: tiles,
              ),
            ),
          )
        else
          ...tiles,
      ],
    );
  }
}
