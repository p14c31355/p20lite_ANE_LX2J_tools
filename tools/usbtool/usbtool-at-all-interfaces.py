import usb.core, usb.util, time

dev = usb.core.find(idVendor=0x12d1, idProduct=0x107e)
if dev is None:
    print("Device not found")
    exit(1)

try:
    dev.set_configuration()
except:
    pass

# Try all three vendor interfaces (0, 1, 2)
for iface_num in [0, 1, 2]:
    print(f"\n=== Interface {iface_num} ===")
    ep_in = None
    ep_out = None
    for cfg in dev:
        for intf in cfg:
            if intf.bInterfaceNumber == iface_num:
                for ep in intf:
                    if usb.util.endpoint_direction(ep.bEndpointAddress) == usb.util.ENDPOINT_OUT:
                        ep_out = ep
                    elif usb.util.endpoint_direction(ep.bEndpointAddress) == usb.util.ENDPOINT_IN:
                        ep_in = ep
    
    if not ep_out or not ep_in:
        print("EPs not found")
        continue
    
    try:
        dev.write(ep_out.bEndpointAddress, b'AT\r', timeout=3000)
        time.sleep(0.3)
        data = dev.read(ep_in.bEndpointAddress, 64, timeout=3000)
        print(f"AT: {data.tobytes()!r}")
        
        dev.write(ep_out.bEndpointAddress, b'ATI\r', timeout=3000)
        time.sleep(0.3)
        data = dev.read(ep_in.bEndpointAddress, 64, timeout=3000)
        print(f"ATI: {data.tobytes()!r}")
    except usb.core.USBTimeoutError:
        print("timeout")
    except usb.core.USBError as e:
        print(f"error: {e}")
