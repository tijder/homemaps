/// De vervoerswijzen, met de naam van Valhalla's `costing`.
enum Profiel {
  auto('auto'),
  fiets('bicycle'),
  lopen('pedestrian');

  const Profiel(this.costing);
  final String costing;
}
