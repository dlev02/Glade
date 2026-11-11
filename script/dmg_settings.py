# Layout of the install disk image, read by dmgbuild: the app on the left, the
# Applications folder on the right, and an arrow between them.
app = defines["app"]
files = [app]
symlinks = {"Applications": "/Applications"}
format = "UDZO"
background = defines["background"]
default_view = "icon-view"
window_rect = ((240, 240), (640, 400))
icon_size = 128
text_size = 13
icon_locations = {"Glade.app": (170, 185), "Applications": (470, 185)}
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
