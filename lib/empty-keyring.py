"""Sets the GNOME login keyring password to empty, so it unlocks without a login.

Reads the current login password from stdin. Uses gnome-keyring's
ChangeWithMasterPassword D-Bus method, the same call Seahorse makes.
"""

import sys

from gi.repository import Gio, GLib

BUS_NAME = "org.freedesktop.secrets"
SERVICE_PATH = "/org/freedesktop/secrets"
LOGIN_KEYRING = "/org/freedesktop/secrets/collection/login"


def _open_plain_session(bus: Gio.DBusConnection) -> str:
    reply = bus.call_sync(
        BUS_NAME,
        SERVICE_PATH,
        "org.freedesktop.Secret.Service",
        "OpenSession",
        GLib.Variant("(sv)", ("plain", GLib.Variant("s", ""))),
        GLib.VariantType("(vo)"),
        Gio.DBusCallFlags.NONE,
        -1,
        None,
    )
    return reply.unpack()[1]


def _change_password(bus: Gio.DBusConnection, session: str, original: str, new: str) -> None:
    def secret(password: str) -> tuple[str, bytes, bytes, str]:
        return (session, b"", password.encode(), "text/plain")

    bus.call_sync(
        BUS_NAME,
        SERVICE_PATH,
        "org.gnome.keyring.InternalUnsupportedGuiltRiddenInterface",
        "ChangeWithMasterPassword",
        GLib.Variant("(o(oayays)(oayays))", (LOGIN_KEYRING, secret(original), secret(new))),
        None,
        Gio.DBusCallFlags.NONE,
        -1,
        None,
    )


def main() -> int:
    login_password = sys.stdin.readline().rstrip("\n")
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    session = _open_plain_session(bus)

    try:
        _change_password(bus, session, login_password, "")
    except GLib.Error as wrong_password:
        try:
            _change_password(bus, session, "", "")
        except GLib.Error:
            print(f"could not empty the login keyring password: {wrong_password.message}", file=sys.stderr)
            return 1
        print("login keyring password was already empty")
        return 0

    print("login keyring password is now empty")
    return 0


if __name__ == "__main__":
    sys.exit(main())
