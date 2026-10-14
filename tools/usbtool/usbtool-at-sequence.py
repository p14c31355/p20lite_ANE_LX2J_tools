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

def send(cmd, delay=0.3):
    try:
        dev.write(ep_out.bEndpointAddress, cmd.encode('ascii'), timeout=3000)
        time.sleep(delay)
        try:
            data = dev.read(ep_in.bEndpointAddress, 256, timeout=3000)
            return data.tobytes().decode('ascii', errors='replace').strip()
        except usb.core.USBTimeoutError:
            return "timeout"
    except usb.core.USBError as e:
        return f"error: {e}"

# Try standard AT commands that might initialize the session
cmds = [
    "AT+CRESET\r",
    "AT+CFUN?\r",
    "AT+CGMI\r",
    "AT+CGMM\r",
    "AT+CGMR\r",
    "AT+CPIN?\r",
]

for cmd in cmds:
    print(f"{cmd.strip()}: {send(cmd)}")

print("\n--- Now try privileged commands ---")
privileged = ["ATI\r", "AT^GETPORTMODE\r"]
for cmd in privileged:
    print(f"{cmd.strip()}: {send(cmd)}")
