#!/usr/bin/env python3
"""Run the real UFS sync function in a host harness; inspect the built r8s DTB."""
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
TREE = Path(os.environ.get('R8S_TEST_KERNEL_TREE', ROOT / 'out/validation/ufs-clocks/linux'))


class UfsClocks(unittest.TestCase):
    def test_sync_commands_and_soc_scope(self):
        source = (TREE / 'drivers/ufs/host/ufs-exynos.c').read_text()
        header = (TREE / 'drivers/ufs/host/ufs-exynos.h').read_text()
        flag = 'EXYNOS_UFS_OPT_SKIP_SYNC_PATTERN_MASK'
        variants = re.findall(r'static const struct exynos_ufs_drv_data (\w+) = \{(.*?)\n};', source, re.S)
        self.assertEqual([name for name, body in variants if flag in body], ['exynos990_ufs_drvs'])
        function = source[source.index('static void exynos_ufs_config_sync_pattern_mask('):source.index('static int exynos_ufs_pre_pwr_mode(')]
        defines = '\n'.join(line for line in header.splitlines() if line.startswith('#define EXYNOS_UFS_OPT_'))
        harness = r'''
#include <assert.h>
#include <stdint.h>
typedef uint8_t u8;
typedef uint32_t u32;
#define BIT(x) (1U << (x))
#define max_t(t,a,b) ((a) > (b) ? (a) : (b))
#define RX_SYNC_MASK_LENGTH 0x321
#define UIC_ARG_MIB_SEL(id,lane) (((id) << 16) | (lane))
#define for_each_ufs_rx_lane(ufs,i) for ((i)=0; (i)<2; (i)++)
struct ufs_hba { int unused; };
struct exynos_ufs { struct ufs_hba *hba; unsigned opts; };
struct ufs_pa_layer_attr { unsigned gear_rx, gear_tx; };
static int calls;
static unsigned attrs[4], values[4];
static void record(unsigned attr, unsigned val) { assert(calls < 4); attrs[calls]=attr; values[calls++]=val; }
static long exynos_ufs_calc_time_cntr(struct exynos_ufs *u, long ns) { (void)u; return ns; }
static void exynos_ufs_enable_ov_tm(struct ufs_hba *h) { (void)h; record(0x9540,1); }
static void exynos_ufs_disable_ov_tm(struct ufs_hba *h) { (void)h; record(0x9540,0); }
static void ufshcd_dme_set(struct ufs_hba *h, unsigned attr, unsigned val) { (void)h; record(attr,val); }
'''
        main = r'''
int main(void) {
 struct ufs_hba h={0}; struct exynos_ufs u={&h,0};
 for (unsigned gear=1; gear<=4; gear++) {
  struct ufs_pa_layer_attr p={gear,gear};
  for (unsigned skip=0; skip<=1; skip++) {
   calls=0; u.opts=skip ? EXYNOS_UFS_OPT_SKIP_SYNC_PATTERN_MASK : 0;
   exynos_ufs_config_sync_pattern_mask(&u,&p);
   assert(calls == ((skip || gear==4) ? 0 : 4));
   if(calls) {
    assert(attrs[0]==0x9540 && values[0]==1);
    assert(attrs[1]==(0x321<<16) && attrs[2]==((0x321<<16)|1));
    assert(attrs[3]==0x9540 && values[3]==0);
   }
  }
 }
}
'''
        with tempfile.TemporaryDirectory() as temp:
            src = Path(temp)/'sync.c'; exe = Path(temp)/'sync'
            src.write_text(harness + defines + '\n' + function + main)
            subprocess.run(['cc', '-Wall', '-Wextra', '-Werror', str(src), '-o', str(exe)], check=True)
            subprocess.run([str(exe)], check=True)

    def test_audio_provider_and_consumer_disabled_in_built_dtb(self):
        dtc = TREE / 'scripts/dtc/dtc'
        dtb = TREE / 'arch/arm64/boot/dts/exynos/exynos990-r8s.dtb'
        text = subprocess.run([str(dtc), '-I', 'dtb', '-O', 'dts', str(dtb)], check=True, capture_output=True, text=True).stdout
        for node in ['power-domain@15861900', 'clock-controller@18c00000']:
            body = text.split(node + ' {', 1)[1].split('};', 1)[0]
            self.assertIn('status = "disabled";', body)
        clock = text.split('ufs-core-clock {', 1)[1].split('};', 1)[0]
        self.assertIn(f'clock-frequency = <0x{166562500:x}>;', clock)
        ufs = text.split('ufs@13100000 {', 1)[1].split('};', 1)[0]
        self.assertIn('status = "okay";', ufs)

    def test_clkout_guard_preserves_of_children(self):
        text = (TREE / 'drivers/soc/samsung/exynos-pmu.c').read_text()
        guard = text.index('if (!of_device_is_compatible(dev->of_node, "samsung,exynos850-pmu"))')
        add = text.index('ret = devm_mfd_add_devices', guard)
        populate = text.index('if (devm_of_platform_populate(dev))', add)
        self.assertIn('\n\t}\n', text[add:populate])
        self.assertNotIn('return 0;', text[guard:populate])


if __name__ == '__main__':
    unittest.main()
