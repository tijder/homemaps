import 'dart:math';

import 'package:flutter/material.dart';

/// Zo breed wordt een categorie hooguit; op een computer blijft hij zo
/// leesbaar.
const instellingenMaxBreedte = 720.0;

/// De rand links en rechts: 16, of meer als het scherm breder is dan
/// [instellingenMaxBreedte], zodat de inhoud in het midden staat.
double instellingenRand(double breedte) =>
    max(16, (breedte - instellingenMaxBreedte) / 2);

/// Een categorie: een lijst die op een breed scherm in het midden staat, met
/// de schuifbalk toch aan de rand.
class InstellingenLijst extends StatelessWidget {
  const InstellingenLijst({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, ruimte) => ListView(
      padding: EdgeInsets.symmetric(
        horizontal: instellingenRand(ruimte.maxWidth),
        vertical: 16,
      ),
      children: children,
    ),
  );
}

/// Een groep instellingen: een kop, eventueel uitleg, en een kaart met de
/// regels erin.
class InstellingenSectie extends StatelessWidget {
  const InstellingenSectie({
    super.key,
    this.titel,
    this.uitleg,
    required this.children,
  });

  final String? titel;
  final String? uitleg;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final thema = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (titel != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                titel!,
                style: thema.textTheme.titleSmall?.copyWith(
                  color: thema.colorScheme.primary,
                ),
              ),
            ),
          if (uitleg != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(uitleg!, style: thema.textTheme.bodySmall),
            ),
          Card.filled(
            margin: EdgeInsets.zero,
            color: thema.colorScheme.surfaceContainerLow,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

/// Een blok met ruimte eromheen in een [InstellingenSectie], voor velden en
/// knoppen die geen `ListTile` zijn.
class SectieBlok extends StatelessWidget {
  const SectieBlok({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.all(16), child: child);
}
