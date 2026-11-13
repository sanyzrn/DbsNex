#!/usr/bin/env python3
"""Nex 2.6.23 Theme Atelier — the fourteen redesigned ramps.

Design language: each theme keeps its identity (name, motif, idea) and gets a
designed surface ramp in the Soft UI shape — light: near-white page, one
tint-step to the card, another to the elevated fill; dark: deep hue-cast
page, lighter card, lighter still elevated fill. Each theme carries two
accent steps: `accent` is the deep, text-safe one (marks, focus rings, quiet
button labels — 4.5:1 on its own card) and `fab` is the vibrant one (the
capture button, a graphical glyph at the 3:1 floor), the same split the
shipped Soft Light theme makes between #006DCC and #0084F7.

2026-era palette directions:
- still     warm bone neutrals, quiet sage — the flat, restful one
- paper     analog journaling: cream stock, sepia ink, brass accents
- autumn    terracotta and ember on peach cream / umber-plum dusk
- blossom   rose atelier: petal white, atelier rose / aubergine and orchid
- forest    pine and mist / deep woodland with mint-pine light
- turquoise Isfahan tilework: ice white, tile teal / deep tile night
- saffron   golden saffron on warm ivory / tobacco night with marigold
- midnight  iris violet on periwinkle white / indigo with a violet glow
- ocean     marine blue on sea mist / abyssal blue with sea-glass cyan
- graphite  soft-industrial concrete greys, silver ink — colourless by design
- bauhaus   gallery white, ink and vermilion / charcoal workshop, signal red
- porcelain blue-white glaze stitched with kintsugi gold / deep glaze + gold
- circuit   engineering cyan on a pale board / signal traces on midnight PCB
- afterimage electric olive on chartreuse mist / void with electric lime
"""

from palette_checker import Ramp


class Theme:
    def __init__(self, tid, light, dark):
        self.id = tid
        self.light = light
        self.dark = dark


THEMES = [
    Theme('still',  # ------------------------------ warm bone + quiet sage
        Ramp(
            page='#FAFAF6', card='#F0F1EA', elevated='#E4E6DC',
            ink='#252B27', muted='#565F58', line='#D6DBD0', outline='#6F7A70',
            accent='#486553', on_accent='#FFFFFF', fill='#486553', fill_ink='#FFFFFF',
            container='#DFE8DE', container_ink='#233E2D',
            fab='#557A63', fab_ink='#FFFFFF',
        ),
        Ramp(
            page='#161A17', card='#1F2521', elevated='#2A312C',
            ink='#E6E9E2', muted='#B8C2B8', line='#383F39', outline='#9AA89B',
            accent='#B1C9B7', on_accent='#1C3427', fill='#B1C9B7', fill_ink='#1C3427',
            container='#344C3C', container_ink='#D8E8DA',
            fab='#B1C9B7', fab_ink='#1C3427',
        ),
    ),
    Theme('paper',  # ------------------------------ cream stock, sepia, brass
        Ramp(
            page='#FBF7EE', card='#F3EDDE', elevated='#E9E1CD',
            ink='#2E2416', muted='#6B5D48', line='#E4DBC6', outline='#857457',
            accent='#7A571C', on_accent='#FFFFFF', fill='#7A571C', fill_ink='#FFFFFF',
            container='#F0E4C8', container_ink='#5C4310',
            fab='#8F6524', fab_ink='#FFFFFF',
        ),
        Ramp(
            page='#1A1510', card='#241D15', elevated='#2F271C',
            ink='#EFE4D0', muted='#B3A288', line='#3B3125', outline='#8D7D63',
            accent='#E3B365', on_accent='#241A08', fill='#E3B365', fill_ink='#241A08',
            container='#3B2F1D', container_ink='#F0D9AC',
            fab='#E3B365', fab_ink='#241A08',
        ),
    ),
    Theme('autumn',  # ---------------------------- terracotta, ember, dusk
        Ramp(
            page='#FCF5EF', card='#F5E9E0', elevated='#EBD9CC',
            ink='#2F201A', muted='#6E564A', line='#EBDACC', outline='#8A6A58',
            accent='#A04621', on_accent='#FFFFFF', fill='#A04621', fill_ink='#FFFFFF',
            container='#F3DCCB', container_ink='#7A3414',
            fab='#C25E1E', fab_ink='#FFFFFF',
        ),
        Ramp(
            page='#1D1512', card='#271D18', elevated='#33261F',
            ink='#F2E4DA', muted='#BBA698', line='#403027', outline='#9A8272',
            accent='#F0854D', on_accent='#1F0F05', fill='#F0854D', fill_ink='#1F0F05',
            container='#43281A', container_ink='#F5C9A8',
            fab='#F0854D', fab_ink='#1F0F05',
        ),
    ),
    Theme('blossom',  # -------------------------- rose atelier, aubergine
        Ramp(
            page='#FDF7F9', card='#F6EBF0', elevated='#ECDEE6',
            ink='#2B202B', muted='#6C5A6B', line='#EFDFE6', outline='#86667F',
            accent='#A93A5E', on_accent='#FFFFFF', fill='#A93A5E', fill_ink='#FFFFFF',
            container='#F5DCE5', container_ink='#8C2E52',
            fab='#C25277', fab_ink='#FFFFFF',
        ),
        Ramp(
            page='#1D151B', card='#281E26', elevated='#342831',
            ink='#F1E6EC', muted='#BDAEC0', line='#3F303D', outline='#9C85A0',
            accent='#F191B6', on_accent='#2A0E1C', fill='#F191B6', fill_ink='#2A0E1C',
            container='#46283A', container_ink='#F7C9DA',
            fab='#F191B6', fab_ink='#2A0E1C',
        ),
    ),
    Theme('forest',  # ----------------------------- pine, mist, woodland
        Ramp(
            page='#F6F9F4', card='#EBF0E7', elevated='#DFE7DA',
            ink='#202820', muted='#556055', line='#DFE6D9', outline='#75816F',
            accent='#3C6F54', on_accent='#FFFFFF', fill='#3C6F54', fill_ink='#FFFFFF',
            container='#DCEAD9', container_ink='#2C5238',
            fab='#468465', fab_ink='#FFFFFF',
        ),
        Ramp(
            page='#121714', card='#1A211C', elevated='#242C25',
            ink='#E2E8DF', muted='#A8B5A7', line='#2C352D', outline='#8FA292',
            accent='#9CD0AC', on_accent='#0D1A10', fill='#9CD0AC', fill_ink='#0D1A10',
            container='#24402C', container_ink='#C6E8CE',
            fab='#9CD0AC', fab_ink='#0D1A10',
        ),
    ),
    Theme('turquoise',  # ------------------------ Isfahan tile, lapis night
        Ramp(
            page='#F4FAFA', card='#E7F3F3', elevated='#DAEBEB',
            ink='#122A29', muted='#4E6968', line='#DEEAEC', outline='#6E8C8A',
            accent='#0B6E77', on_accent='#FFFFFF', fill='#0B6E77', fill_ink='#FFFFFF',
            container='#D2EAEA', container_ink='#0A5A62',
            fab='#0E7C86', fab_ink='#FFFFFF',
        ),
        Ramp(
            page='#0B1E21', card='#122A2E', elevated='#1A373C',
            ink='#DEEFEF', muted='#9BB8BA', line='#204045', outline='#7FA3A6',
            accent='#4FC8D4', on_accent='#03181B', fill='#4FC8D4', fill_ink='#03181B',
            container='#123E46', container_ink='#B8ECEF',
            fab='#4FC8D4', fab_ink='#03181B',
        ),
    ),
    Theme('saffron',  # --------------------------- saffron gold, warm ivory
        Ramp(
            page='#FDF8EC', card='#F6EFD9', elevated='#EDE3C6',
            ink='#2D2512', muted='#6C5F41', line='#F0E7CD', outline='#877648',
            accent='#8F5400', on_accent='#FFFFFF', fill='#8F5400', fill_ink='#FFFFFF',
            container='#F4E5BC', container_ink='#7A4C03',
            fab='#C07200', fab_ink='#FFFFFF',
        ),
        Ramp(
            page='#191307', card='#231B0C', elevated='#2E2412',
            ink='#F0E6C8', muted='#B7A87E', line='#3A2E17', outline='#978660',
            accent='#F2B705', on_accent='#1F1503', fill='#F2B705', fill_ink='#1F1503',
            container='#3E2E10', container_ink='#F5D98F',
            fab='#F2B705', fab_ink='#1F1503',
        ),
    ),
    Theme('midnight',  # ------------------------- iris violet, indigo glow
        Ramp(
            page='#F7F6FC', card='#EEEDF8', elevated='#E2E0F1',
            ink='#211E33', muted='#585474', line='#E5E3F3', outline='#767197',
            accent='#634CD7', on_accent='#FFFFFF', fill='#634CD7', fill_ink='#FFFFFF',
            container='#E4DEF9', container_ink='#4B38AE',
            fab='#6750D8', fab_ink='#FFFFFF',
        ),
        Ramp(
            page='#131226', card='#1B1A33', elevated='#252342',
            ink='#E4E1F2', muted='#AFA9CB', line='#2C2A4A', outline='#8D87B3',
            accent='#A996F5', on_accent='#171335', fill='#A996F5', fill_ink='#171335',
            container='#312B5E', container_ink='#D4CBF8',
            fab='#A996F5', fab_ink='#171335',
        ),
    ),
    Theme('ocean',  # ------------------------------ marine blue, sea glass
        Ramp(
            page='#F5F9FC', card='#E9F1F7', elevated='#DCE8F0',
            ink='#1B2A36', muted='#52677A', line='#E0EBF3', outline='#70899C',
            accent='#1565A8', on_accent='#FFFFFF', fill='#1565A8', fill_ink='#FFFFFF',
            container='#D8E8F4', container_ink='#0F4C81',
            fab='#1565A8', fab_ink='#FFFFFF',
        ),
        Ramp(
            page='#0A1622', card='#101F30', elevated='#17293D',
            ink='#DDE9F2', muted='#98AEC1', line='#1E324A', outline='#7C97AE',
            accent='#74BFDD', on_accent='#07131D', fill='#74BFDD', fill_ink='#07131D',
            container='#14374F', container_ink='#BCE0F2',
            fab='#74BFDD', fab_ink='#07131D',
        ),
    ),
    Theme('graphite',  # ------------------------ concrete greys, silver ink
        Ramp(
            page='#F5F5F5', card='#ECECEC', elevated='#E0E0E0',
            ink='#232323', muted='#5C5C5C', line='#E4E4E4', outline='#787878',
            accent='#55585D', on_accent='#FFFFFF', fill='#55585D', fill_ink='#FFFFFF',
            container='#DEDEDE', container_ink='#3A3D42',
            fab='#55585D', fab_ink='#FFFFFF',
        ),
        Ramp(
            page='#121212', card='#1B1B1B', elevated='#262626',
            ink='#EDEDED', muted='#ABABAB', line='#2B2B2B', outline='#8A8A8A',
            accent='#C6C9CE', on_accent='#14161A', fill='#C6C9CE', fill_ink='#14161A',
            container='#2F3237', container_ink='#D9DCE1',
            fab='#9EA3AA', fab_ink='#14161A',
        ),
    ),
    Theme('bauhaus',  # ------------------------ gallery white, vermilion
        Ramp(
            page='#FAFAF7', card='#F0EFEA', elevated='#E4E3DC',
            ink='#1E1C19', muted='#5B5850', line='#E8E6DF', outline='#7C7869',
            accent='#B83322', on_accent='#FFFFFF', fill='#B83322', fill_ink='#FFFFFF',
            container='#F1DCD5', container_ink='#8C2416',
            fab='#C13524', fab_ink='#FFFFFF',
        ),
        Ramp(
            page='#161513', card='#201E1B', elevated='#2B2926',
            ink='#ECE9E3', muted='#B0ABA1', line='#35322E', outline='#948E82',
            accent='#F26248', on_accent='#1F0C06', fill='#F26248', fill_ink='#1F0C06',
            container='#402420', container_ink='#F5C1B4',
            fab='#F25C41', fab_ink='#1F0C06',
        ),
    ),
    Theme('porcelain',  # ------------------- blue-white glaze, kintsugi gold
        Ramp(
            page='#F9FAFC', card='#EFF1F6', elevated='#E2E5EE',
            ink='#20242F', muted='#565E70', line='#E5E8F1', outline='#737C92',
            accent='#7C5F1C', on_accent='#FFFFFF', fill='#7C5F1C', fill_ink='#FFFFFF',
            container='#EFE3C4', container_ink='#6B5110',
            fab='#8C6C22', fab_ink='#FFFFFF',
        ),
        Ramp(
            page='#101623', card='#182130', elevated='#212C40',
            ink='#E2E7F0', muted='#A3AEC4', line='#273349', outline='#8794AD',
            accent='#E8C56A', on_accent='#1D1603', fill='#E8C56A', fill_ink='#1D1603',
            container='#383322', container_ink='#EDD9A0',
            fab='#E8C56A', fab_ink='#1D1603',
        ),
    ),
    Theme('circuit',  # ------------------- engineering cyan, midnight board
        Ramp(
            page='#F5FAFB', card='#E8F3F5', elevated='#DBEBEE',
            ink='#15242A', muted='#4E6A72', line='#DFECEF', outline='#6E8C95',
            accent='#067076', on_accent='#FFFFFF', fill='#067076', fill_ink='#FFFFFF',
            container='#D3EBEC', container_ink='#045E65',
            fab='#007F86', fab_ink='#FFFFFF',
        ),
        Ramp(
            page='#071417', card='#0D2024', elevated='#142C31',
            ink='#DCEEF0', muted='#93B3B8', line='#193338', outline='#77989E',
            accent='#29C9C9', on_accent='#02161A', fill='#29C9C9', fill_ink='#02161A',
            container='#0F3A3E', container_ink='#A8E8E8',
            fab='#29C9C9', fab_ink='#02161A',
        ),
    ),
    Theme('afterimage',  # ------------------ electric olive, optical rhythm
        Ramp(
            page='#F8FAF2', card='#EDF1E2', elevated='#DFE7D0',
            ink='#212917', muted='#59644A', line='#E6EBD8', outline='#79855F',
            accent='#536D00', on_accent='#FFFFFF', fill='#536D00', fill_ink='#FFFFFF',
            container='#E3ECC8', container_ink='#465F04',
            fab='#5C7700', fab_ink='#FFFFFF',
        ),
        Ramp(
            page='#101208', card='#171D0E', elevated='#202814',
            ink='#EBEFDC', muted='#ADBBA0', line='#27311B', outline='#8C9C7C',
            accent='#B5E23C', on_accent='#101603', fill='#B5E23C', fill_ink='#101603',
            container='#2A3512', container_ink='#D8F0A0',
            fab='#B5E23C', fab_ink='#101603',
        ),
    ),
]
