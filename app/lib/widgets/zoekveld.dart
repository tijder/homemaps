import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../l10n/app_localizations.dart';
import '../models/plaats.dart';
import '../providers/diensten.dart';
import '../providers/plekken.dart';

/// Eén vakje van de route: toont de gekozen plaats, en zoekt bij het typen.
class Zoekveld extends ConsumerStatefulWidget {
  const Zoekveld({
    super.key,
    required this.label,
    required this.plaats,
    required this.onGekozen,
    required this.onGewist,
    this.nabij,
    this.pictogram = Icons.place_outlined,
    this.zwevend = false,
    this.voor,
    this.mijnLocatie,
  });

  final String label;
  final Plaats? plaats;
  final ValueChanged<Plaats> onGekozen;
  final VoidCallback onGewist;

  /// Het midden van de kaart: resultaten daar in de buurt komen bovenaan.
  final LatLng? Function()? nabij;
  final IconData pictogram;

  /// De zoekbalk van het zoekscherm: zonder rand en label, de suggesties in
  /// dezelfde kaart eronder.
  final bool zwevend;

  /// Vóór het tekstvak, bijvoorbeeld de sleepgreep van de routelijst.
  final Widget? voor;

  /// Levert je eigen plek (en vraagt zo nodig toestemming). Null als het niet
  /// lukte; de aanroeper heeft dan al gezegd waarom. Zonder deze functie staat
  /// "Mijn locatie" niet in de suggesties.
  final Future<Plaats?> Function()? mijnLocatie;

  @override
  ConsumerState<Zoekveld> createState() => _ZoekveldState();
}

class _ZoekveldState extends ConsumerState<Zoekveld> {
  final _tekst = TextEditingController();
  final _focus = FocusNode();
  Timer? _wacht;
  Timer? _sluit;
  CancelToken? _lopend;
  List<Plaats> _resultaten = const [];

  /// De suggesties zijn open: het vakje heeft de focus, of had die net (zie de
  /// focus-listener).
  bool _open = false;

  /// Wat er in het vakje hoort te staan als er niet getypt wordt. Een eigen veld
  /// en niet `widget.plaats`: bij het kiezen verliest het vakje de focus vóórdat
  /// de planner de nieuwe plaats heeft teruggegeven, en dan zou de keuze meteen
  /// weer worden weggepoetst.
  String _naam = '';

  String _weergave(Plaats? plaats) =>
      plaats?.weergave(AppLocalizations.of(context)) ?? '';

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (_focus.hasFocus) {
        _sluit?.cancel();
        setState(() => _open = true);
        return;
      }
      // Verlaten zonder te kiezen: terug naar wat er stond. De suggesties gaan pas
      // even later weg -- een klik óp een suggestie haalt in sommige browsers eerst
      // de focus weg, en dan was de lijst verdwenen voordat de klik aankwam.
      _tekst.text = _naam;
      _sluit?.cancel();
      _sluit = Timer(const Duration(milliseconds: 250), () {
        if (mounted && !_focus.hasFocus) {
          setState(() {
            _resultaten = const [];
            _open = false;
          });
        }
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Hier en niet in initState: de naam van "Mijn locatie" komt uit de
    // vertaling, en die is in initState nog niet te lezen.
    _naam = _weergave(widget.plaats);
    if (!_focus.hasFocus) _tekst.text = _naam;
  }

  @override
  void didUpdateWidget(Zoekveld oud) {
    super.didUpdateWidget(oud);
    if (oud.plaats != widget.plaats) {
      _naam = _weergave(widget.plaats);
      if (!_focus.hasFocus) _tekst.text = _naam;
    }
  }

  @override
  void dispose() {
    _wacht?.cancel();
    _sluit?.cancel();
    _lopend?.cancel();
    _tekst.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _getypt(String tekst) {
    // "Mijn locatie" hangt af van wat er getypt is.
    setState(() {});
    _wacht?.cancel();
    // Niet bij elke toets een verzoek: pas na een korte pauze.
    _wacht = Timer(const Duration(milliseconds: 250), () => _zoek(tekst));
  }

  Future<void> _zoek(String tekst) async {
    _lopend?.cancel();
    final photon = ref.read(photonProvider);
    if (photon == null) return;
    final annuleer = _lopend = CancelToken();
    try {
      final gevonden = await photon.zoek(
        tekst,
        nabij: widget.nabij?.call(),
        annuleer: annuleer,
      );
      if (mounted && !annuleer.isCancelled) {
        setState(() => _resultaten = gevonden);
      }
    } on DioException {
      // Een mislukte suggestie is geen melding waard; de lijst blijft leeg.
      if (mounted && !annuleer.isCancelled) {
        setState(() => _resultaten = const []);
      }
    }
  }

  /// [onthoud]: een zoekresultaat of recente plek komt (weer) vooraan in de
  /// recente; thuis, werk en "Mijn locatie" niet.
  void _kies(Plaats plaats, {bool onthoud = false}) {
    if (onthoud) ref.read(plekkenProvider.notifier).onthoud(plaats);
    _sluit?.cancel();
    _tekst.text = _naam = _weergave(plaats);
    setState(() {
      _resultaten = const [];
      _open = false;
    });
    widget.onGekozen(plaats);
    _focus.unfocus();
  }

  Future<void> _kiesMijnLocatie() async {
    final plaats = await widget.mijnLocatie!();
    if (plaats != null && mounted) _kies(plaats);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    // Bovenaan zolang er niets of het begin van "Mijn locatie" getypt is.
    final getypt = _tekst.text.trim().toLowerCase();
    final metMijnLocatie =
        widget.mijnLocatie != null &&
        _open &&
        (getypt.isEmpty ||
            getypt == _naam.toLowerCase() ||
            l.mijnLocatie.toLowerCase().startsWith(getypt));
    // Thuis en werk als het vakje leeg is of je hun naam begint te typen; de
    // recente als het leeg is, of die waar het getypte in voorkomt.
    final plekken = ref.watch(plekkenProvider);
    final leeg = getypt.isEmpty || getypt == _naam.toLowerCase();
    final vast = !_open
        ? const <(IconData, String, Plaats)>[]
        : [
            for (final (pictogram, label, plaats) in [
              (Icons.home_outlined, l.thuis, plekken.thuis),
              (Icons.work_outline, l.werk, plekken.werk),
            ])
              if (plaats != null &&
                  (leeg || label.toLowerCase().startsWith(getypt)))
                (pictogram, label, plaats),
          ];
    final recent = !_open
        ? const <Plaats>[]
        : leeg
        ? plekken.recent.take(5).toList()
        : plekken.recent
              .where((p) => p.naam.toLowerCase().contains(getypt))
              .take(3)
              .toList();
    final suggesties =
        _resultaten.isNotEmpty ||
        metMijnLocatie ||
        vast.isNotEmpty ||
        recent.isNotEmpty;
    final veld = TextField(
      controller: _tekst,
      focusNode: _focus,
      onChanged: _getypt,
      onSubmitted: (_) {
        if (_resultaten.isNotEmpty) _kies(_resultaten.first, onthoud: true);
      },
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        labelText: widget.zwevend ? null : widget.label,
        hintText: widget.zwevend ? widget.label : l.zoekPlaats,
        prefixIcon: Icon(widget.pictogram),
        isDense: true,
        border: widget.zwevend ? InputBorder.none : const OutlineInputBorder(),
        contentPadding: widget.zwevend
            ? const EdgeInsets.symmetric(vertical: 14)
            : null,
        suffixIcon: widget.plaats == null && _tekst.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.clear),
                tooltip: l.verwijderen,
                onPressed: () {
                  _tekst.clear();
                  _naam = '';
                  setState(() => _resultaten = const []);
                  widget.onGewist();
                },
              ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.voor == null)
          veld
        else
          Row(
            children: [
              widget.voor!,
              Expanded(child: veld),
            ],
          ),
        if (widget.zwevend && suggesties) const Divider(height: 1),
        if (metMijnLocatie)
          ListTile(
            dense: true,
            leading: Icon(
              Icons.my_location,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: Text(l.mijnLocatie),
            onTap: _kiesMijnLocatie,
          ),
        for (final (pictogram, label, plaats) in vast)
          ListTile(
            dense: true,
            leading: Icon(
              pictogram,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: Text(label),
            subtitle: Text(
              [
                plaats.naam,
                plaats.omschrijving,
              ].where((t) => t.isNotEmpty).join(', '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => _kies(
              Plaats(naam: label, omschrijving: plaats.naam, punt: plaats.punt),
            ),
          ),
        for (final plaats in recent)
          ListTile(
            dense: true,
            leading: const Icon(Icons.history),
            title: Text(
              plaats.naam,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: plaats.omschrijving.isEmpty
                ? null
                : Text(
                    plaats.omschrijving,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
            onTap: () => _kies(plaats, onthoud: true),
          ),
        for (final plaats in _resultaten)
          ListTile(
            dense: true,
            leading: const Icon(Icons.place_outlined),
            title: Text(
              _weergave(plaats),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: plaats.omschrijving.isEmpty
                ? null
                : Text(
                    plaats.omschrijving,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
            onTap: () => _kies(plaats, onthoud: true),
          ),
      ],
    );
  }
}
