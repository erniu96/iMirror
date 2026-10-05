# dmgbuild settings for the iMirror disk image. Paths come from -D on the
# command line (see Scripts/make-dmg.sh); background@2x.png is picked up
# automatically next to background.png.
import os.path

app = defines["app"]  # noqa: F821
app_name = os.path.basename(app)

format = "UDZO"
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}

background = defines["background"]  # noqa: F821
window_rect = ((200, 120), (640, 400))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
icon_size = 128
text_size = 13
icon_locations = {
    app_name: (170, 190),
    "Applications": (470, 190),
}

# Show the app icon on the mounted volume as well.
icon = os.path.join(app, "Contents", "Resources", "AppIcon.icns")
