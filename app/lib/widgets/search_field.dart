import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
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

class _SearchFieldState extends ConsumerState<SearchField> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  Timer? _close;
  CancelToken? _inFlight;
  List<Place> _results = const [];

  /// The suggestions are open: the field has focus, or just had it (see the
  /// focus listener).
  bool _open = false;

  /// What the field should show when nobody is typing. A field of its own and
  /// not `widget.place`: when choosing, the field loses focus before the
  /// planner has returned the new place, and then the choice would be wiped
  /// out right away.
  String _label = '';

  String _display(Place? place) =>
      place?.display(AppLocalizations.of(context)) ?? '';

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (_focus.hasFocus) {
        _close?.cancel();
        setState(() => _open = true);
        return;
      }
      // Left without choosing: back to what was there. The suggestions only go
      // away a moment later -- in some browsers a click on a suggestion first
      // removes the focus, and then the list was gone before the click arrived.
      _text.text = _label;
      _close?.cancel();
      _close = Timer(const Duration(milliseconds: 250), () {
        if (mounted && !_focus.hasFocus) {
          setState(() {
            _results = const [];
            _open = false;
          });
        }
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
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

  @override
  void dispose() {
    _debounce?.cancel();
    _close?.cancel();
    _inFlight?.cancel();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _typed(String text) {
    // "My location" depends on what has been typed.
    setState(() {});
    _debounce?.cancel();
    // Not a request on every key: only after a short pause.
    _debounce = Timer(const Duration(milliseconds: 250), () => _find(text));
  }

  Future<void> _find(String text) async {
    _inFlight?.cancel();
    final photon = ref.read(photonProvider);
    if (photon == null) return;
    final cancel = _inFlight = CancelToken();
    try {
      final found = await photon.search(
        text,
        near: widget.near?.call(),
        cancel: cancel,
      );
      if (mounted && !cancel.isCancelled) {
        setState(() => _results = found);
      }
    } on DioException {
      // A failed suggestion isn't worth a message; the list stays empty.
      if (mounted && !cancel.isCancelled) {
        setState(() => _results = const []);
      }
    }
  }

  /// [remember]: a search result or recent place goes (back) to the front of
  /// the recent ones; home, work and "My location" don't.
  void _choose(Place place, {bool remember = false}) {
    if (remember) ref.read(savedPlacesProvider.notifier).remember(place);
    _close?.cancel();
    _text.text = _label = _display(place);
    setState(() {
      _results = const [];
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
    final suggestions =
        _results.isNotEmpty ||
        withMyLocation ||
        fixed.isNotEmpty ||
        recent.isNotEmpty;
    final field = TextField(
      controller: _text,
      focusNode: _focus,
      onChanged: _typed,
      onSubmitted: (_) {
        if (_results.isNotEmpty) _choose(_results.first, remember: true);
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
                  setState(() => _results = const []);
                  widget.onCleared();
                },
              ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.before == null)
          field
        else
          Row(
            children: [
              widget.before!,
              Expanded(child: field),
            ],
          ),
        if (widget.floating && suggestions) const Divider(height: 1),
        if (withMyLocation)
          ListTile(
            dense: true,
            leading: Icon(
              Icons.my_location,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: Text(l.myLocation),
            onTap: _chooseMyLocation,
          ),
        for (final (icon, label, place) in fixed)
          ListTile(
            dense: true,
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
          ListTile(
            dense: true,
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
          ListTile(
            dense: true,
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
      ],
    );
  }
}
