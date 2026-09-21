import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../l10n/app_localizations.dart';
import '../models/plaats.dart';
import '../providers/diensten.dart';

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
  });

  final String label;
  final Plaats? plaats;
  final ValueChanged<Plaats> onGekozen;
  final VoidCallback onGewist;

  /// Het midden van de kaart: resultaten daar in de buurt komen bovenaan.
  final LatLng? Function()? nabij;
  final IconData pictogram;

  @override
  ConsumerState<Zoekveld> createState() => _ZoekveldState();
}

class _ZoekveldState extends ConsumerState<Zoekveld> {
  final _tekst = TextEditingController();
  final _focus = FocusNode();
  Timer? _wacht;
  CancelToken? _lopend;
  List<Plaats> _resultaten = const [];

  /// Wat er in het vakje hoort te staan als er niet getypt wordt. Een eigen veld
  /// en niet `widget.plaats`: bij het kiezen verliest het vakje de focus vóórdat
  /// de planner de nieuwe plaats heeft teruggegeven, en dan zou de keuze meteen
  /// weer worden weggepoetst.
  String _naam = '';

  @override
  void initState() {
    super.initState();
    _tekst.text = _naam = widget.plaats?.naam ?? '';
    _focus.addListener(() {
      // Verlaten zonder te kiezen: terug naar wat er stond.
      if (!_focus.hasFocus) {
        _tekst.text = _naam;
        setState(() => _resultaten = const []);
      }
    });
  }

  @override
  void didUpdateWidget(Zoekveld oud) {
    super.didUpdateWidget(oud);
    if (oud.plaats != widget.plaats) {
      _naam = widget.plaats?.naam ?? '';
      if (!_focus.hasFocus) _tekst.text = _naam;
    }
  }

  @override
  void dispose() {
    _wacht?.cancel();
    _lopend?.cancel();
    _tekst.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _getypt(String tekst) {
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

  void _kies(Plaats plaats) {
    _tekst.text = _naam = plaats.naam;
    setState(() => _resultaten = const []);
    widget.onGekozen(plaats);
    _focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _tekst,
          focusNode: _focus,
          onChanged: _getypt,
          onSubmitted: (_) {
            if (_resultaten.isNotEmpty) _kies(_resultaten.first);
          },
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: l.zoekPlaats,
            prefixIcon: Icon(widget.pictogram),
            isDense: true,
            border: const OutlineInputBorder(),
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
        ),
        for (final plaats in _resultaten)
          ListTile(
            dense: true,
            leading: const Icon(Icons.place_outlined),
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
            onTap: () => _kies(plaats),
          ),
      ],
    );
  }
}
