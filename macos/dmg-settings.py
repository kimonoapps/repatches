# dmgbuild layout for Mawaqit.dmg; release.sh passes app, icon and background via -D.
app = defines["app"]

format = "UDZO"
volume_name = "Mawaqit"
icon = defines["icon"]
files = [app]
symlinks = {"Applications": "/Applications"}
hide_extensions = ["Mawaqit.app"]

background = defines["background"]
window_rect = ((200, 140), (640, 400))
default_view = "icon-view"
show_toolbar = False
show_sidebar = False
show_pathbar = False
show_status_bar = False
show_tab_view = False
show_icon_preview = False

arrange_by = None
icon_size = 128
text_size = 14
# Centres line up with the arrow drawn by Assets/make-dmg-background.swift.
icon_locations = {"Mawaqit.app": (170, 200), "Applications": (470, 200)}
