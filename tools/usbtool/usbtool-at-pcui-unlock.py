import usb.core, usb.util, time

dev = usb.core.find(idVendor=0x12d1, idProduct=0x107e)
if dev is None:
    print("Device not found")
    exit(1)

try:
    dev.set_configuration()
except:
    pass

ep_in = None
ep_out = None
for cfg in dev:
    for intf in cfg:
        if intf.bInterfaceNumber == 1:
            for ep in intf:
                if usb.util.endpoint_direction(ep.bEndpointAddress) == usb.util.ENDPOINT_OUT:
                    ep_out = ep
                elif usb.util.endpoint_direction(ep.bEndpointAddress) == usb.util.ENDPOINT_IN:
                    ep_in = ep

if not ep_out or not ep_in:
    print("EPs not found")
    exit(1)

cmds = [
    "AT+PCUID=1\r",
    "AT+PCUIAUTH=1\r",
    "AT+DIAGAUTH=1\r",
    "AT+UNLOCK\r",
    "AT+PCUISET=1\r",
    "AT+PCUI=1\r",
    "AT$PCUID\r",
    "AT$PCUI\r",
    "AT$AUTH\r",
    "AT$UNLOCK\r",
]

for cmd in cmds:
    try:
        dev.write(ep_out.bEndpointAddress, cmd.encode('ascii'), timeout=3000)
        time.sleep(0.5)
        try:
            data = dev.read(ep_in.bEndpointAddress, 64, timeout=3000)
            print(f"{cmd.strip()!r}: {data.tobytes()!r}")
        except usb.core.USBTimeoutError:
            print(f"{cmd.strip()!r}: timeout")
    except usb.core.USBError as e:
        print(f"{cmd.strip()!r}: error {e}")
