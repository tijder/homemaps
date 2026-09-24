import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../router/app_router.dart';
import 'categorie.dart';
import 'sectie.dart';

/// Vanaf deze breedte naast elkaar: de categorieën links, de gekozen rechts.
/// Dezelfde grens als op de kaart.
const _breed = 800.0;

/// De instellingen. Smal: een lijst categorieën, en een categorie als eigen
/// pagina (`/instellingen/<categorie>`). Breed (een computer): beide naast
/// elkaar.
@RoutePage()
class InstellingenScreen extends StatefulWidget {
  const InstellingenScreen({super.key, @PathParam('categorie') this.categorie});

  /// Het [InstellingenCategorie.pad]; null voor de lijst.
  final String? categorie;

  @override
  State<InstellingenScreen> createState() => _InstellingenScreenState();
}

class _InstellingenScreenState extends State<InstellingenScreen> {
  /// Breed: wat er rechts staat, als je in de lijst iets anders koos.
  InstellingenCategorie? _gekozen;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final uitAdres = InstellingenCategorie.van(widget.categorie);
    return LayoutBuilder(
      builder: (context, ruimte) {
        if (ruimte.maxWidth >= _breed) {
          final gekozen = _gekozen ?? uitAdres ?? InstellingenCategorie.kaart;
          return Scaffold(
            appBar: AppBar(title: Text(l.instellingen)),
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 300,
                  child: _CategorieLijst(
                    breed: true,
                    gekozen: gekozen,
                    onKies: (c) => setState(() => _gekozen = c),
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: _Detail(gekozen, key: ValueKey(gekozen))),
              ],
            ),
          );
        }
        if (uitAdres != null) {
          return Scaffold(
            appBar: AppBar(title: Text(uitAdres.titel(l))),
            body: uitAdres.inhoud(),
          );
        }
        return Scaffold(
          appBar: AppBar(title: Text(l.instellingen)),
          body: _CategorieLijst(
            breed: false,
            onKies: (c) => context.router.push(
              InstellingenCategorieRoute(categorie: c.pad),
            ),
          ),
        );
      },
    );
  }
}

/// `/instellingen/<categorie>`: dezelfde instellingen, met die categorie
/// open. Een eigen pagina, want auto_route wil per route een eigen naam.
@RoutePage()
class InstellingenCategorieScreen extends StatelessWidget {
  const InstellingenCategorieScreen({
    super.key,
    @PathParam('categorie') required this.categorie,
  });

  final String categorie;

  @override
  Widget build(BuildContext context) =>
      InstellingenScreen(categorie: categorie);
}

/// Breed: de titel van de categorie boven zijn inhoud, even ver ingesprongen.
class _Detail extends StatelessWidget {
  const _Detail(this.categorie, {super.key});

  final InstellingenCategorie categorie;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return LayoutBuilder(
      builder: (context, ruimte) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              instellingenRand(ruimte.maxWidth) + 16,
              24,
              instellingenRand(ruimte.maxWidth),
              0,
            ),
            child: Text(
              categorie.titel(l),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          Expanded(child: categorie.inhoud()),
        ],
      ),
    );
  }
}

/// De categorieën per groep, met hoe ze ervoor staan. Smal in kaarten zoals
/// de rest van de instellingen; breed als zijbalk met de gekozen gemarkeerd.
class _CategorieLijst extends ConsumerWidget {
  const _CategorieLijst({
    required this.breed,
    required this.onKies,
    this.gekozen,
  });

  final bool breed;
  final InstellingenCategorie? gekozen;
  final ValueChanged<InstellingenCategorie> onKies;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final thema = Theme.of(context);
    final groepen = [
      for (final groep in InstellingenGroep.values)
        (
          groep,
          [
            for (final c in InstellingenCategorie.zichtbare)
              if (c.groep == groep) c,
          ],
        ),
    ];
    Widget regel(InstellingenCategorie c) => ListTile(
      leading: Icon(c.pictogram),
      title: Text(c.titel(l)),
      subtitle: Text(
        c.samenvatting(ref, l),
        maxLines: breed ? 1 : 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: breed ? null : const Icon(Icons.chevron_right),
      selected: c == gekozen,
      selectedTileColor: breed ? thema.colorScheme.secondaryContainer : null,
      selectedColor: breed ? thema.colorScheme.onSecondaryContainer : null,
      shape: breed ? const StadiumBorder() : null,
      onTap: () => onKies(c),
    );

    if (breed) {
      return ListView(
        padding: const EdgeInsets.all(12),
        children: [
          for (final (groep, categorieen) in groepen) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                groep.titel(l),
                style: thema.textTheme.titleSmall?.copyWith(
                  color: thema.colorScheme.primary,
                ),
              ),
            ),
            for (final c in categorieen) regel(c),
          ],
        ],
      );
    }
    return InstellingenLijst(
      children: [
        for (final (groep, categorieen) in groepen)
          InstellingenSectie(
            titel: groep.titel(l),
            children: [for (final c in categorieen) regel(c)],
          ),
      ],
    );
  }
}
