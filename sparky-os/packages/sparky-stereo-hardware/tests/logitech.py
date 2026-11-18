#!/usr/bin/python3
"""Logitech offers are visible choices; detection alone installs no program."""
from pathlib import Path
import subprocess,sys,tempfile,unittest
HERE=Path(__file__).resolve().parents[1]
BASE={'laptop':'1\n','cpuinfo':'vendor_id : AuthenticAMD\n','firmware-packages':'','lspci':'','lsusb':'','hid-uevents':'','input-properties':'','architecture':'amd64\n'}
class Offers(unittest.TestCase):
    def plan(self,changes):
        with tempfile.TemporaryDirectory() as folder:
            for name,value in (BASE|changes).items():(Path(folder)/name).write_text(value)
            return subprocess.run([sys.executable,str(HERE/'lib/detect.py'),folder,str(HERE/'share')],capture_output=True,text=True,check=True).stdout
    def test_unifying_receiver_is_offered_not_installed(self):
        out=self.plan({'lsusb':'Bus 001 Device 002: ID 046d:c52b Logitech Unifying Receiver\n'})
        self.assertIn('offer\topenlogi\t046d:c52b',out)
        self.assertNotIn('package\tsolaar\n',out)
        self.assertNotIn('package\topenlogi\n',out)
    def test_bluetooth_hidpp_device(self):
        out=self.plan({'hid-uevents':'HID_ID=0005:0000046D:0000B023\nHID_NAME=MX Master 3\n'})
        self.assertIn('offer\topenlogi\t046d:b023',out)
    def test_new_hidpp_device_identified_by_kernel_driver(self):
        out=self.plan({'hid-uevents':'DRIVER=logitech-hidpp\nHID_ID=0003:0000046D:0000FFFF\n'})
        self.assertIn('offer\topenlogi\t046d:ffff',out)
    def test_litra_glow_and_beam(self):
        for product in ('c900','c901'):
            self.assertIn('offer\topenlogi\t046d:'+product,self.plan({'lsusb':f'Bus 001 Device 002: ID 046d:{product} Logitech Litra\n'}))
    def test_logitech_uvc_class(self):
        self.assertIn('offer\topenlogi\t046d:082d',self.plan({'usb-video':'046d:082d\n'}))
    def test_unknown_camera_product_still_matches_uvc(self):
        self.assertIn('offer\topenlogi\t046d:ffff',self.plan({'usb-video':'046d:ffff\n'}))
    def test_no_logitech_control_and_unrelated_vendor(self):
        for changes in ({},{'lsusb':'Bus 001 Device 002: ID 046d:ffff unknown\n'},{'usb-video':'1234:082d\n'},{'hid-uevents':'HID_ID=0005:00001234:0000B023\n'}):
            self.assertNotIn('offer\topenlogi',self.plan(changes))
    def test_existing_copy_is_left_to_the_person(self):
        out=self.plan({'lsusb':'Bus 001 Device 002: ID 046d:c52b Receiver\n','openlogi-present':'yes\n'})
        self.assertNotIn('offer\topenlogi',out)
        self.assertNotIn('package\tsolaar\n',out)
if __name__=='__main__':unittest.main()
