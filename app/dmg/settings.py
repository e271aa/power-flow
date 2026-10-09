# A disposição da janela do DMG, para o dmgbuild (https://dmgbuild.readthedocs.io).
# O build.sh passa a app, o fundo e o ícone com -D; os tamanhos e as posições
# acompanham o dmg/background.svg (660 x 400 pt, ícones centrados em y 180).
import os

app = defines["app"]
app_name = os.path.basename(app)

format = "UDZO"
files = [app]
symlinks = {"Applications": "/Applications"}
icon = defines["icon"]
background = defines["background"]

# Perto do centro dos ecrãs dos portáteis mais comuns (1440 × 900 a 1512 × 982 pt).
# O Finder conta o y a partir de cima. Com «Preferir separadores: Sempre» o
# DMG abre como separador de uma janela já aberta, e isto não se aplica.
window_rect = ((420, 250), (660, 400))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
sidebar_width = 0

icon_size = 128
text_size = 13
arrange_by = None
label_pos = "bottom"
icon_locations = {
    app_name: (165, 180),
    "Applications": (495, 180),
    # O fundo e o ícone do volume: escondidos e, para um Finder que mostre os
    # ficheiros escondidos, fora da área da janela, em vez de ao lado da app.
    ".background.tiff": (165, 700),
    ".VolumeIcon.icns": (495, 700),
}

# Escondidos mesmo num Finder que mostre os ficheiros começados por ponto.
hide = [".background.tiff", ".VolumeIcon.icns"]
# «PowerFlow», e não «PowerFlow.app», mesmo com as extensões à vista.
hide_extensions = [app_name]
