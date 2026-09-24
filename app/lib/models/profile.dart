/// The modes of transport, with Valhalla's `costing` name.
enum Profile {
  car('auto'),
  bike('bicycle'),
  walk('pedestrian');

  const Profile(this.costing);
  final String costing;
}
