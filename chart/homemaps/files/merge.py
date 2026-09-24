import sqlite3
import sys

detail, world = sys.argv[1], sys.argv[2]

db = sqlite3.connect(detail)
db.execute("ATTACH DATABASE ? AS w", (world,))


def one(sql):
    return db.execute(sql).fetchone()[0]


# The two runs must not overlap in zoom level: otherwise there is no telling
# which tile wins, and an INSERT on the primary key would fail.
lowest_detail = one("SELECT min(zoom_level) FROM main.tiles_shallow")
highest_world = one("SELECT max(zoom_level) FROM w.tiles_shallow")
if highest_world >= lowest_detail:
    sys.exit(f"zoom levels overlap: world up to z{highest_world}, detail from z{lowest_detail}")

# With --compact-db (the default) Planetiler writes no `tiles` table but
# tiles_shallow (z/x/y -> tile_data_id) plus tiles_data (id -> blob), so that
# identical tiles -- the ocean -- are stored only once. The ids of the two files
# both start at zero and therefore have to be shifted apart.
offset = one("SELECT coalesce(max(tile_data_id), 0) + 1 FROM main.tiles_data")
offset -= min(0, one("SELECT coalesce(min(tile_data_id), 0) FROM w.tiles_data"))

with db:
    db.execute(
        "INSERT INTO main.tiles_data (tile_data_id, tile_data) "
        "SELECT tile_data_id + ?, tile_data FROM w.tiles_data",
        (offset,),
    )
    db.execute(
        "INSERT INTO main.tiles_shallow (zoom_level, tile_column, tile_row, tile_data_id) "
        "SELECT zoom_level, tile_column, tile_row, tile_data_id + ? FROM w.tiles_shallow",
        (offset,),
    )
    # minzoom and bounds come from the world run. That is necessary: a client that
    # follows the TileJSON (MapLibre does) requests no tiles outside `bounds`.
    # `center` stays that of the detail run, so the viewer opens on the Netherlands.
    db.execute(
        "UPDATE main.metadata SET value = (SELECT value FROM w.metadata x WHERE x.name = main.metadata.name) "
        "WHERE name IN ('minzoom', 'bounds')"
    )

print(
    "merged: z%d-z%d, %d tiles, bounds %s"
    % (
        one("SELECT min(zoom_level) FROM main.tiles_shallow"),
        one("SELECT max(zoom_level) FROM main.tiles_shallow"),
        one("SELECT count(*) FROM main.tiles_shallow"),
        one("SELECT value FROM main.metadata WHERE name = 'bounds'"),
    )
)
