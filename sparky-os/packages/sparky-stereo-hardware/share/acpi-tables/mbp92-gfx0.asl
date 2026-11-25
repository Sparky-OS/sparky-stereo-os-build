/*
 * Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/11/17
 * Copyright 2026 under the GNU GPL3 License
 *
 * MacBookPro9,2 (13 inch, mid 2012; Intel graphics only). Its firmware's EC query _Q80 ("performance capability
 * change") ends with Notify (\_SB.PCI0.P0P2.GFX0, ...), the discrete GPU of the 15 inch model, which this model does
 * not have. Linux cannot resolve the name, aborts the method and logs two ACPI errors for every event (about 15 a
 * second). This table gives the name an object that is "not present", so the Notify resolves and goes nowhere.
 * Compiled at build time (iasl) into /usr/share/sparky/sparky-stereo-hardware/acpi-tables/mbp92-gfx0.aml and put
 * into the boot images of that model only (sparky-stereo-known-machines; ORDER 665).
 */
DefinitionBlock ("", "SSDT", 2, "SPARKY", "MBP92GFX", 0x00000001)
{
    External (_SB_.PCI0.P0P2, DeviceObj)

    Scope (\_SB.PCI0.P0P2)
    {
        Device (GFX0)
        {
            Name (_ADR, Zero)
            Method (_STA, 0, NotSerialized)
            {
                Return (Zero)
            }
        }
    }
}
