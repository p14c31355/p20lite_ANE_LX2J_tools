import usb.core, usb.util, time

dev = usb.core.find(idVendor=0x12d1, idProduct=0x107e)
if dev is None:
    print("Device not found")
    exit(1)

try:
    dev.set_configuration()
except:
    pass

def try_cmd(iface, cmd):
    """Try to send AT command to specific interface"""
    ep_in = None
    ep_out = None
    for cfg in dev:
        for intf in cfg:
            if intf.bInterfaceNumber == iface:
                for ep in intf:
                    if usb.util.endpoint_direction(ep.bEndpointAddress) == usb.util.ENDPOINT_OUT:
                        ep_out = ep
                    elif usb.util.endpoint_direction(ep.bEndpointAddress) == usb.util.ENDPOINT_IN:
                        ep_in = ep
    
    if not ep_out or not ep_in:
        return "no eps"
    
    try:
        dev.write(ep_out.bEndpointAddress, cmd.encode('ascii'), timeout=3000)
        time.sleep(0.3)
        try:
            data = dev.read(ep_in.bEndpointAddress, 64, timeout=3000)
            return data.tobytes().decode('ascii', errors='replace').strip()
        except usb.core.USBTimeoutError:
            return "timeout"
    except usb.core.USBError as e:
        return f"error: {e}"

print("Testing all interfaces with AT$QCDMG command:")
for iface in [0, 1, 2]:
    result = try_cmd(iface, "AT$QCDMG=115200\r")
    print(f"  Interface {iface}: {result}")

print("\nTesting all interfaces with various AT commands:")
cmds = ["ATI", "AT+CGMI", "AT^VERSION", "AT&V"]
for cmd in cmds:
    for iface in [0, 1, 2]:
        result = try_cmd(iface, cmd + "\r")
        print(f"  Interface {iface} - {cmd}: {result}")
