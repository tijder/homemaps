import sqlite3
import sys

detail, wereld = sys.argv[1], sys.argv[2]

db = sqlite3.connect(detail)
db.execute("ATTACH DATABASE ? AS w", (wereld,))


def een(sql):
    return db.execute(sql).fetchone()[0]


# De twee runs mogen elkaar in zoomniveau niet overlappen: anders is niet te
# zeggen welke tegel wint, en zou een INSERT op de primaire sleutel stuklopen.
laagste_detail = een("SELECT min(zoom_level) FROM main.tiles_shallow")
hoogste_wereld = een("SELECT max(zoom_level) FROM w.tiles_shallow")
if hoogste_wereld >= laagste_detail:
    sys.exit(f"zoomniveaus overlappen: wereld t/m z{hoogste_wereld}, detail vanaf z{laagste_detail}")

# Planetiler schrijft met --compact-db (de default) geen tabel `tiles` maar
# tiles_shallow (z/x/y -> tile_data_id) plus tiles_data (id -> blob), zodat
# identieke tegels -- de oceaan -- maar een keer worden opgeslagen. De id's van de
# twee bestanden beginnen allebei bij nul en moeten dus uit elkaar geschoven.
verschuiving = een("SELECT coalesce(max(tile_data_id), 0) + 1 FROM main.tiles_data")
verschuiving -= min(0, een("SELECT coalesce(min(tile_data_id), 0) FROM w.tiles_data"))

with db:
    db.execute(
        "INSERT INTO main.tiles_data (tile_data_id, tile_data) "
        "SELECT tile_data_id + ?, tile_data FROM w.tiles_data",
        (verschuiving,),
    )
    db.execute(
        "INSERT INTO main.tiles_shallow (zoom_level, tile_column, tile_row, tile_data_id) "
        "SELECT zoom_level, tile_column, tile_row, tile_data_id + ? FROM w.tiles_shallow",
        (verschuiving,),
    )
    # minzoom en bounds komen uit de wereld-run. Dat moet: een client die de
    # TileJSON volgt (MapLibre doet dat) vraagt buiten `bounds` geen tegels op.
    # `center` blijft die van de detail-run, zodat de viewer op Nederland opent.
    db.execute(
        "UPDATE main.metadata SET value = (SELECT value FROM w.metadata x WHERE x.name = main.metadata.name) "
        "WHERE name IN ('minzoom', 'bounds')"
    )

print(
    "samengevoegd: z%d-z%d, %d tegels, bounds %s"
    % (
        een("SELECT min(zoom_level) FROM main.tiles_shallow"),
        een("SELECT max(zoom_level) FROM main.tiles_shallow"),
        een("SELECT count(*) FROM main.tiles_shallow"),
        een("SELECT value FROM main.metadata WHERE name = 'bounds'"),
    )
)
