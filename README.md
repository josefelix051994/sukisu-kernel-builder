# SukiSU-Ultra 内核编译工具

依据官方集成教程 [sukisu.org/zh/guide/how-to-integrate](https://sukisu.org/zh/guide/how-to-integrate) 编写的一键式内核编译工具。

**核心流程:选设备型号 → 选内核版本 → 自动选集成分支 → 自动下载源码和工具链 → 集成 SukiSU-Ultra → 编译内核 → 打包产物。**

> 🌐 **在线编译**: 本仓库自带 GitHub Actions 工作流与网页,不用本地环境也能编译 ——
> 打开 <https://xingyiqaq.github.io/sukisu-kernel-builder/>,选机型/版本,一键触发云端编译,实时看进度、下载产物。

```
┌─────────────┐   ┌──────────────┐   ┌────────────────┐   ┌──────────────┐
│ 选设备型号   │ → │ 选内核版本    │ → │ 自动选集成分支  │ → │ 自动编译打包  │
│ devices.conf│   │ (仓库+分支)   │   │ KSU 分支        │   │ AK3 zip / .ko│
└─────────────┘   └──────────────┘   └────────────────┘   └──────────────┘
```

## 〇、网页在线编译(GitHub Actions)

无需本地 Linux 环境,浏览器里选好机型直接编译:

1. 打开 <https://xingyiqaq.github.io/sukisu-kernel-builder/>
2. 填入一个 GitHub Token(需 `repo` + `workflow` 权限;只保存在浏览器 localStorage,不会上传)
3. 选设备型号 → 内核版本 → SukiSU 分支 → 点「开始编译」
4. 页面实时显示步骤状态(每 3 秒刷新)与构建日志(每 10 秒刷新;GitHub 对进行中任务的日志接口有延迟,想看完整实时日志可在页面上点「在 GitHub 打开」);完成后直接点「下载」拿 AnyKernel3 zip / kernelsu.ko

也可在 GitHub 仓库页面 **Actions → SukiSU Kernel Build → Run workflow** 手动触发。

**注意事项(公共 runner 限制):**
- 每个编译任务在 GitHub 公共 runner(2 核 7GB 内存)上执行,一次完整编译约 30 分钟~3 小时(取决于内核),单任务上限 6 小时;
- 产物保留 **14 天**(GitHub artifact 策略),请及时下载;
- 公共仓库的编译任务对所有人可见,如需私密构建可 fork 成私有仓库(私有仓库用 GitHub Pages 需要付费套餐,网页请改在本地打开 `index.html`)。

## 一、环境要求(本地编译)

- **Linux**(Ubuntu 20.04+ / Debian / WSL2),脚本不能直接在 Windows 上运行
- 网络通畅(需访问 GitHub 与 android.googlesource.com)
- 磁盘 **50GB+** 空闲(工具链约 3GB + 内核源码数 GB + 编译产物)
- 内存 **8GB+**(编译内核较吃内存),CPU 核越多越快

WSL2 用户先装 Ubuntu 发行版,进入后:

```bash
sudo apt update && sudo apt install -y git curl make gcc g++ bc bison flex libssl-dev libncurses-dev zip cpio python3
```

## 二、快速开始

```bash
# 进入工具目录(Windows 的 E 盘在 WSL 里是 /mnt/e)
cd /mnt/e/文档/deepseek-harness/default-workspace/sukisu-kernel-builder

# 交互式运行: 按提示选型号、选内核版本、选集成分支即可
bash build.sh
```

**交互示例**(选 Redmi K40 的 Android 11 内核,集成分支自动选择):

```
  [信息] 请选择设备型号:
      1) Redmi K40 / POCO F3
      2) Redmi K20 Pro / Mi 9T Pro
      ...
  >> 输入编号选择, 或输入关键词过滤 [默认 1]: k40        ← 支持关键词过滤
  ...
  >> 输入编号选择 [默认 1]: 1                            ← 该设备只有 1 个内核版本时自动跳过
  [信息] 集成分支(自动): builtin (GKI 设备用 main, 传统内核用 builtin; 可用 --ksu 覆盖)
  [信息] ==================== 编译任务 ====================
  设备       : Redmi K40 / POCO F3 (alioth)
  内核版本   : Android 11 · Linux 4.19
  仓库/分支  : https://github.com/MiCode/Xiaomi_Kernel_OpenSource @ alioth-r-oss
  ...
  开始编译? [Y/n]
```

随后自动完成:下载 Clang 工具链 → 克隆内核源码 → 集成 SukiSU(自动选分支)→ 兼容性修复 → 生成 defconfig 并启用 `CONFIG_KSU` 等 → `make -j$(nproc)` 编译 → 打包。

## 三、命令行参数(非交互 / 自动化)

| 参数 | 说明 |
|---|---|
| `--list` | 列出设备库全部条目 |
| `--device <id>` | 直接指定设备 ID(如 `alioth`) |
| `--version <n>` | 该设备第 n 个内核版本(配合 `--device`) |
| `--branch <名称>` | 直接指定内核分支,可单独使用自动反查设备 |
| `--repo <url>` | 自定义内核仓库(绕过设备库,配合 `--branch`) |
| `--defconfig <路径>` | 指定 defconfig(如 `vendor/alioth_user_defconfig`) |
| `--kver <x.y>` / `--android <n>` | 自定义源时声明内核/Android 版本(用于选编译器) |
| `--gki` | 标记为 GKI 通用内核(默认内置模式, 需要 LKM 加 `--ksu-mode m`) |
| `--ksu <main\|builtin>` | SukiSU 集成分支(默认: GKI 设备=main, 传统内核=builtin) |
| `--ksu-mode <y\|m>` | `y`=内置(默认),`m`=LKM 模块(需要目标树导出 kernelsu.ko 依赖符号;builtin 分支只支持 y) |
| `--kpm` | 启用 KPM(`CONFIG_KPM=y`) |
| `--debug-ksu` | 启用 `CONFIG_KSU_DEBUG` |
| `--susfs` | 启用 `CONFIG_KSU_SUSFS`(要求内核已集成 susfs4ksu 补丁) |
| `--clang <分支:目录>` | 覆盖 Clang 版本(如 `llvm-r522817:clang-r522817`) |
| `--gcc` | 强制 GCC 4.9 工具链(老内核) |
| `--jobs <n>` | 并行编译数(默认 nproc) |
| `--no-pack` | 只编译不打包 |
| `--resume` | 复用已有的 `work/kernel` 源码 |
| `--clean` | 开始前清空 `work/` 目录 |
| `--yes` | 跳过确认直接开始 |
| `--dry-run` | 演练模式: 只打印将执行的编译任务, 不下载/编译 |

示例:

```bash
bash build.sh --device alioth --version 1 --ksu main --yes          # 小米 K40, 全自动
bash build.sh --branch oneplus/SM8250_R_11.0 --ksu builtin          # 一加 8T OOS11, builtin 分支
bash build.sh --device gki-a15 --ksu-mode m --yes                   # 通用 GKI A15, 产出 kernelsu.ko
bash build.sh --repo https://github.com/xxx/kernel --branch main \
              --defconfig vendor/foo_defconfig --kver 5.15 --android 13 --gki
```

## 四、设备库(devices.conf)

已收录并通过 GitHub API 核实的条目(**177 条 / 146 台设备**):

| 厂商 | 设备 | 内核版本 |
|---|---|---|
| 小米(全型号) | 小米/红米/POCO 共 146 台(从小米开源 `Xiaomi_Kernel_OpenSource` 自动枚举,完整清单见 [builds/README.md](builds/README.md)) | 3.18 / 4.4 / 4.9 / 4.14 / 4.19 / 5.4 / 5.10 / 5.15 / 6.1 / 6.6 |
| 一加 | 7/7 Pro/7T/7T Pro、8/8 Pro、8T/9R、9/9 Pro、9RT | 4.14 / 4.19 / 5.4 / 5.15 |
| 通用 GKI | Android 12 ~ 16(对应 KMI: 5.10 / 5.15 / 6.1 / 6.6 / 6.12) | GKI |

**添加自己的设备**:编辑 `devices.conf`,按格式追加一行(共 9 列,`|` 分隔):

```
设备ID|版本标签|设备显示名|内核仓库URL|分支名|内核版本|Android版本|GKI标志|defconfig提示
alioth|Android 11 · Linux 4.19|Redmi K40 / POCO F3|https://github.com/MiCode/Xiaomi_Kernel_OpenSource|alioth-r-oss|4.19|11|0|vendor/alioth_user_defconfig
```

- `GKI标志`:`1` = GKI 通用内核(默认内置模式),`0` = 非 GKI(默认内置模式)
- `defconfig提示` 可留空(自动按设备 ID 探测),支持 glob(如 `vendor/kona*`)
- **片段配置**(`vendor/*_consolidate.config`、`*_GKI.config` 等不足 200 行的文件):工具会自动以 `gki_defconfig` 为基础合并片段,并裁掉 FULL LTO / KASAN / DWARF 等调试选项(否则 2 核 runner 极易超时)
- **中文型号**:网页设备下拉按**中文型号**排序显示,数据在 `tools/device_zh.tsv`(每行 `<机型代码>\t<中文型号>`,多地区同款用 ` / ` 分隔,如 `alioth	红米K40 / 小米11X / POCO F3`)。生成链:`tools/data/mi_devices.yml`(MIUI 机型表,含各地区的 codename→营销名)→ `node tools/gen_device_zh.js`(去地区后缀、翻译成中文、每台最多 3 个名字、中文名在前)→ `tools/device_zh.tsv`。想改某台的显示名,改脚本里的 `OVERRIDE` 或直接改 TSV,然后重跑生成器即可。
- 改完 `devices.conf` 后请重新生成派生文件:

```bash
bash gen_devices.sh > devices.json    # 网页用的设备清单(必须用 bash 重定向)
node tools/normalize_devices.js        # 按中文名排序 + 中文名在前(展示层整理)
node tools/gen_device_zh.js            # 如有机型改名/新增, 重生成中文映射后再跑上面两条
bash tools/gen_build_scripts.sh        # 每机型每版本的独立编译脚本(builds/)
```

> 网页第 2 步的设备下拉上方有搜索框,输入中文型号或机型代码(如 `K40`、`alioth`)即可过滤。

> ⚠️ Windows 用户注意:`devices.json` 必须用 **bash 自己的重定向** 生成。PowerShell 的 `>` 会把文件写成 UTF-16LE(带 BOM),浏览器和 CI 都无法解析。在 PowerShell 里请这样调用:
> `& 'C:\Program Files\Git\bin\bash.exe' -c 'bash gen_devices.sh > devices.json'`

## 五、产物说明

产物输出到 `output/` 目录,文件名规则统一为:

```
<品牌>_<机型>_<机型代码>_<内核版本>_SukiSU-<版本>_<日期时间>.zip   (或 .ko)
```

| 模式 | 产物 | 用法 |
|---|---|---|
| 内置(`CONFIG_KSU=y`,非 GKI 默认) | 如 `Redmi_K40+POCO_F3_alioth_4.19.113_SukiSU-v3.0.0_20261120-2003.zip` | TWRP 等 Recovery 刷入(AnyKernel3 格式) |
| LKM(`CONFIG_KSU=m`,`--ksu-mode m` 时) | 如 `Google_Android_15_gki-a15_6.6_SukiSU-v3.0.0_20261120-2003.ko` | SukiSU 管理器 → 安装 → **使用本地 LKM 文件**(仅支持 `.ko`) |

- 品牌/机型来自 `devices.conf` 第 3 列(显示名),例如 `Redmi K40 / POCO F3` → `Redmi_K40+POCO_F3`;
  自动枚举的设备(显示名等于代码)按仓库归属推断品牌(小米内核 → `Xiaomi`),机型字段省略,代码只出现一次;
- 内核版本以克隆后源码 `Makefile` 的 `VERSION.PATCHLEVEL.SUBLEVEL` 为准;
- SukiSU 版本取集成后的 `KernelSU` 目录 `git describe --tags`(拿不到时用短提交);
- 日期时间为北京时间(UTC+8);
- 每次编译同时生成 `output/release-notes.md`(发布备注:设备/内核/SukiSU 版本 + 刷入说明)与 `output/LAST_ARTIFACT`(产物清单),CI 用它们自动创建 GitHub Release。

> ⚠️ 刷机有风险:刷入前务必备份原 boot 分区(卡第一屏时恢复用);部分设备还需考虑 AVB/锁 BL 问题。

## 六、目录结构

```
sukisu-kernel-builder/
├── build.sh               # 主工具(单次编译: 选机型 + 版本 → 产出内核)
├── build-all.sh           # 本地一键全量编译(依次跑 builds/ 下全部脚本)
├── gen_devices.sh         # devices.conf → devices.json(网页用)
├── devices.conf           # 设备库(177 条)
├── builds/                # 【自动生成】每机型每版本的独立编译脚本
│   ├── README.md          #   索引表
│   └── <设备ID>/v<序号>.sh
├── tools/
│   ├── gen_build_scripts.sh  # 生成 builds/ 下的独立脚本
│   └── trigger-all.sh        # 触发云端全量编译(GitHub Actions 矩阵)
├── logs/                  # build-all.sh 的日志与断点状态
├── work/                  # 工作区(可整目录删除)
│   ├── toolchains/        # Clang / GCC 工具链(首次下载后复用)
│   ├── kernel/            # 内核源码 + 已集成的 SukiSU(KernelSU/)
│   ├── AnyKernel3/        # AK3 打包模板
│   └── ak3-pkg/           # 打包临时目录
├── output/                # 最终产物(zip / .ko)
└── build.log              # 编译日志
```

## 七、工作原理(对应教程章节)

1. **下载内核源码** — 按所选设备与版本克隆官方开源内核
2. **集成 SukiSU**(教程 *KernelSU 集成* 部分):`main` 分支优先运行官方 `setup.sh`,失败自动回退 GitHub 手动集成;`builtin` 分支直接走 GitHub 手动集成(确定性最高),等效操作:
   - 克隆 SukiSU 到 `KernelSU/`
   - 符号链接 `KernelSU/kernel → drivers/kernelsu`
   - `drivers/Makefile` 追加 `obj-$(CONFIG_KSU) += kernelsu/`
   - `drivers/Kconfig` 插入 `source "drivers/kernelsu/Kconfig"`
3. **内核配置**(教程 *KSU 配置* 部分),按分支自动启用:
   - `main` 分支(GKI 默认):`CONFIG_KSU=y|m` + `CONFIG_KPROBES=y` + `CONFIG_EXT4_FS=y`
   - `builtin` 分支(传统内核默认,4.4+):`CONFIG_KSU=y`(bool)+ `CONFIG_SECURITY_SELINUX=y` + `CONFIG_KALLSYMS=y/KALLSYMS_ALL=y`;`CONFIG_KSU_SUSFS` 默认显式关闭(需 `--susfs` 且内核已集成 susfs4ksu 补丁)
   - 可选:`--kpm`(KPM)、`--debug-ksu`
   - 集成后自动做**兼容性修复**(main:12 项 4.x 老内核修复;builtin:3 项 4.x 修复,含 static_call.h 守卫、syscall_work、fallthrough),详见 `build.sh` 内注释
4. **编译** — 按 Android 版本自动选择 AOSP Clang 预编译分支(GKI 或 ≥5.10 用 `LLVM=1`;<4.14 或 `--gcc` 用 GCC 4.9)
5. **打包** — 内置模式用 AnyKernel3 打包 Image.gz + DTB(+DTBO);LKM 模式直接输出 `kernelsu.ko`

## 八、常见问题

| 问题 | 解决 |
|---|---|
| 依赖缺失 | 按脚本提示运行 apt 安装命令 |
| Clang 下载失败 | 网络问题;用 `--clang <分支:目录>` 换规格重试,工具链已下载部分会自动复用 |
| 官方 setup.sh 失败 | 工具会自动改用 GitHub 手动集成(等效操作),无需干预 |
| `CONFIG_KSU` 未生效 | 依赖不满足: main 分支需 KPROBES/EXT4_FS, builtin 分支需 SECURITY_SELINUX;检查 `work/kernel/out/.config` |
| 4.14 老内核编译报错 | 改用 `--gcc`;或 `EXTRA_MAKE_ARGS="LLVM_IAS=1" bash build.sh ...` |
| 老内核脚本报 python2 缺失 | 需另装 python2(新发行版可考虑用 pyenv 或升级内核分支) |
| 编译很久/像卡住了 | Actions 只显示单个「组装编译参数并启动构建」步骤, 日志写在 build.log(结束才上传);5.10 厂商树在 2 核 runner 上 2~4 小时属正常, 上限 350 分钟 |
| 想加快重复编译 | 云端已默认启用 **ccache + 工具链缓存**(同设备/版本第二次编译大幅提速);本地可用 `KERNEL_CCACHE=1 bash build.sh ...` |
| 5.10 GKI 树第一次编译就超时 | 片段配置已自动合并到 gki_defconfig 并裁剪 FULL LTO/KASAN/DWARF;仍超时可用 `--jobs 4` 或换 `ubuntu-latest` 大机器(付费) |
| 想换编译参数 | 用环境变量 `EXTRA_MAKE_ARGS` 追加透传给 make 的参数 |
| 中断后重来 | 直接再跑一次 `bash build.sh --resume`(跳过源码/工具链下载);`--clean` 则全部重来 |
| GKI LKM 模块刷入后不生效 | 确认模块 KMI 与设备内核 KMI 一致(用设备对应的 GKI 分支重新编译) |

### 8.1 内核版本兼容性矩阵(实测)

工具内置了针对小米/一加厂商树与老内核的兼容层,实测通过的版本:

| 内核版本 | 实测结果 | 关键兼容处理 |
|---|---|---|
| 6.1 / 6.6 | ✅ 通过 | SELinux 依赖链 + 片段配置按厂家顺序合并(gki_defconfig → `*_GKI.config` → `*_QGKI.config`) |
| 5.15 / 5.10 | ✅ 通过 | `LLVM=1` 显式 `CROSS_COMPILE=aarch64-linux-gnu-`(否则 clang 按 x86 主机目标编译);预构建 `security/selinux` 生成 `flask.h` |
| 5.4 | ✅ 通过(veux) | 同上 + 多片段合并(GKI + QGKI),避免 vmlinux 链接 `undefined reference to qcom_smem_get` 等 |
| 4.19 | ✅ 通过(全类) | `dtc` 的 `yylloc` 重复定义、`KPROBES/EXT4_FS` 依赖、`-Wno-error`(厂商 `subdir-ccflags -Werror` 直接剥离,扫描范围覆盖全树 Makefile/Kbuild + `mm/Makefile`) |
| 4.14 | ✅ 通过(davinci/begonia/biloba/fleur 等) | GCC4.9 binutils 符号链接(`aarch64-linux-gnu-ld` 支持 `-pie -shared` 链接)、`kvcalloc`、vdso 宏前导逗号、`_shipped` dtc 源码补丁、宏形式闭源固件(`#define FTS_UPGRADE_FW_FILE "*.i"` + `#include 宏名`)写占位字节、`-fno-builtin-memcmp/bcmp`(厂商树删了 bcmp)、`.builtin_fw` 段 `ALIGN(8)`(clang LDST64 重定位截断) |
| 4.9 / 4.4 | ✅ 通过(jasmine/dandelion) | `sched/signal.h`→`sched.h`(4.11 前无拆分头)、KPM 自动关闭(4.14 以下不支持)、`fallthrough` 宏、`MIN/MAX` 头 |
| GKI(5.x/6.x)内置 | ✅ 通过(gki-a13/a15 等) | 上游 AOSP 镜像树不是 KMI 完整树, LKM(CONFIG_KSU=m)会在 modpost 阶段缺导出符号; 因此 GKI 也默认内置(KSU=y, main 分支 kprobes), 需要 LKM 请加 `--ksu-mode m` |
| 3.18 | ❌ 不支持 | SukiSU-Ultra builtin 最低要求 Linux 4.4+(3.x 会在预检阶段快速失败并给出明确提示);网页上这类版本标注「⚠ 不支持」,只能演练 |

**厂商源码不完整导致的失败(非工具问题)**:小米开源树存在未公开的目录/文件,工具会尽量自动修补(注释缺失的 `source`/`obj-y` 条目、缺失闭源固件 `.i` 自动写占位字节、平台 HAL 目录按 `CONFIG_MTK_PLATFORM` 正确下钻),但少数机型仍可能因为厂商驱动缺失而链接失败。常见类别与代表机型:

| 类别 | 典型报错 | 代表机型 |
|---|---|---|
| 平台 HAL/符号未公开 | `undefined reference to 'mt_set_pwm_clk_hal'` 等 MTK 平台 HAL | 个别 MTK 4.14 树(已由「obj-y 变量行不误注释」修复,ares/light 已验证通过) |
| 私有头文件缺失 | `fatal error: 'hwid.h' file not found` | marble/garnet/flourite(已自动生成空桩头) |
| 依赖驱动未启用 | `undefined reference to 'mi_disp_register_client'` | lisa/mona(5.4.86)、moonstone(5.4.191)、munch(4.19.157) |
| 厂商源码自身 bug | `use of undeclared identifier 'curve_prime'`(crypto/ecc.c) | breeze(5.10.198) |
| 重复符号定义 | `ld.lld: error: duplicate symbol: __SCK__tp_func_*` | erhu/fuxi(5.15) |
| 老 Makefile 与 GNU make 4.x 不兼容 | `prerequisites cannot be defined in recipes` | dipper(4.9.112) |
| MTK rpmb 私有头缺失 | `use of undeclared identifier 'mtk_mmc_host'`(rpmb-mtk.c) | daumier(5.10.81) |

这类设备编译失败时,步骤日志末尾的「日志中的错误行(最后 8 条)」会直接给出失败原因;产物上传/发布步骤会被标记为「已跳过」。对于同一“设备+版本”组合,最多进行 10 次有记录的修补重试；第 11 次仍失败则从自动编译矩阵剔除,并在本节维护剔除名单。当前尚未完成本轮全量编译,因此名单暂为空;不得将正在运行或历史旧批次统计当作最终结果。

## 九、批量编译(每机型独立脚本 + 一键全量)

### 9.1 每机型每版本的独立脚本 `builds/<设备ID>/v<序号>.sh`

`tools/gen_build_scripts.sh` 会按 `devices.conf` 为**每个"机型 + 内核版本"组合**生成一个独立脚本(当前 177 个),内容就是固定好设备/版本的 `build.sh` 调用:

```bash
bash builds/alioth/v1.sh              # 编译红米 K40 的 4.19 内核
bash builds/marble/v1.sh --dry-run    # 演练, 顺便确认参数
bash builds/op8/v2.sh --kpm           # 追加任意 build.sh 参数
```

生成后不要再手改;改了 `devices.conf` 就重新执行 `bash tools/gen_build_scripts.sh`。完整索引见 [builds/README.md](builds/README.md)。

### 9.2 本地一键全量编译 `build-all.sh`

在 Linux/WSL2 里跑:

```bash
bash build-all.sh                     # 全量串行编译 177 个组合
bash build-all.sh --dry-run --limit 5 # 冒烟: 前 5 个只演练
bash build-all.sh --only alioth,marble
bash build-all.sh --resume            # 只重跑上次失败的(跳过已成功)
bash build-all.sh -j 2                # 2 个并行(内存 ≥16G 再考虑)
bash build-all.sh --fail-fast
```

每个组合的日志在 `logs/<设备>_v<序号>.log`,最终输出成功/失败汇总;`--resume` 的断点记录在 `logs/build-all.state`。

### 9.3 云端一键全量编译 `tools/trigger-all.sh`

不用本地 Linux 环境,直接让 GitHub Actions 跑矩阵(`.github/workflows/build-all.yml`,内部复用 `build.yml` 单设备工作流):

```bash
GH_TOKEN=ghp_xxx bash tools/trigger-all.sh                  # 触发全部(真实编译)
GH_TOKEN=ghp_xxx bash tools/trigger-all.sh --dry-run        # 只做参数检查
GH_TOKEN=ghp_xxx bash tools/trigger-all.sh --only alioth,marble
GH_TOKEN=ghp_xxx bash tools/trigger-all.sh --device gki-a15
GH_TOKEN=ghp_xxx bash tools/trigger-all.sh --max-parallel 3 --wait
```

- `--max-parallel` 控制同时跑几个编译(默认 2;public 仓库 Actions 分钟数免费,但并发过高会争抢 2 核内存导致超时)
- 177 个组合全量编译在云端是**队列排队**的,预计需要数小时到一天,建议先用 `--only` 挑机型
- 也可以在仓库 Actions 页面手动运行「SukiSU 全量编译(矩阵)」工作流,选择 `only` / `max_parallel` / `dry_run` / `publish`

### 9.4 自动发布 Release(统一「内核合集」)

`build.yml` 支持 **编译成功后自动发布**(网页「高级选项 → 自动发布到 Release」,默认勾选;命令行用 `build-all.yml` 的 `publish` 输入):

- 所有机型/版本统一发布到 **一个 Release**:tag 与标题均为 **`内核合集`**,不再为每个组合单独建 Release;
- Release 资产名固定为 **`品牌_机型_机型代码_内核版本.zip`**(如 `Redmi_alioth_4.19.113.zip`): GitHub 的 Release 资产名不支持非 ASCII, 中文机型名会正文/索引里做映射(README「内核下载索引」按中文名列出对应资产);同一组合重新编译会 `--clobber` 覆盖同名资产 → **下载链接长期有效**;
- 各产物的详细说明(内核源码分支、SukiSU 版本与 CONFIG_KSU 模式、编译时间、刷入步骤)仍会写进构建日志与 artifact;机型索引见 README 末尾「内核下载索引」;
- 全量编译默认不发布,需要时给 `build-all.yml` 传 `publish: true`(会把所有成功产物追加进同一个「内核合集」);
- 索引刷新: 改完 `devices.conf` / 中文名后执行 `node tools/gen_kernel_index.js`,会把「内核下载索引」表格重新生成到 README(173 个可编译组合)。

## 免责声明

本工具仅供学习与个人设备使用,编译、刷入内核存在风险,可能造成数据丢失或设备变砖,请自行承担。SukiSU-Ultra、AnyKernel3、各内核源码版权归各自作者所有。

## 十二、内核下载索引(中文机型名)

<!-- KERNEL-INDEX:START -->
共 173 个可编译机型/内核版本组合。资产名格式 `品牌_机型_机型代码_内核版本.zip` —— GitHub 的 Release 资产名不支持中文, 所以资产本身是英文品牌+代码, 中文机型名请看本表首列(下表按中文机型名检索即可)。同一组合重新编译会覆盖同名资产, 链接长期有效。

| 中文机型名 | 机型代码 | 内核版本 | Android | 下载 |
|---|---|---|---|---|
| 红米8 | `olive` | 4.9.193 | 10 | [Xiaomi_olive_4.9.193.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_olive_4.9.193.zip) |
| 红米8 | `olive` | 4.9.112 | 9 | [Xiaomi_olive_4.9.112.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_olive_4.9.112.zip) |
| 红米9 | `lancelot` | 4.14.141 | 10 | [Xiaomi_lancelot_4.14.141.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_lancelot_4.14.141.zip) |
| 红米9A | `dandelion` | 4.9.190 | 10 | [Xiaomi_dandelion_4.9.190.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_dandelion_4.9.190.zip) |
| 红米10 | `selene` | 4.14.186 | 11 | [Xiaomi_selene_4.14.186.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_selene_4.14.186.zip) |
| 红米10X 4G | `merlin` | 4.14.186 | 11 | [Xiaomi_merlin_4.14.186.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_merlin_4.14.186.zip) |
| 红米10X Pro | `bomb` | 4.14.141 | 10 | [Xiaomi_bomb_4.14.141.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_bomb_4.14.141.zip) |
| 红米12 | `fire` | 4.19.191 | 13 | [Xiaomi_fire_4.19.191.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_fire_4.19.191.zip) |
| 红米12C | `earth` | 4.19.191 | 12 | [Xiaomi_earth_4.19.191.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_earth_4.19.191.zip) |
| 红米13 | `moon` | 5.10.198 | 14 | [Xiaomi_moon_5.10.198.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_moon_5.10.198.zip) |
| 红米13C | `gale` | 4.19.191 | 12 | [Xiaomi_gale_4.19.191.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_gale_4.19.191.zip) |
| 红米14R 5G | `flame` | 5.10.198 | 14 | [Xiaomi_flame_5.10.198.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_flame_5.10.198.zip) |
| 红米15 | `creek` | 5.15.167 | 15 | [Xiaomi_creek_5.15.167.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_creek_5.15.167.zip) |
| 红米15R 5G | `spring` | 6.1.93 | 15 | [Xiaomi_spring_6.1.93.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_spring_6.1.93.zip) |
| 红米平板 | `yunluo` | 5.10.101 | 12 | [Xiaomi_yunluo_5.10.101.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_yunluo_5.10.101.zip) |
| 红米平板2 SE | `guitar` | 5.15.185 | 16 | [Xiaomi_guitar_5.15.185.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_guitar_5.15.185.zip) |
| 红米平板2 SE 4G | `erhu` | 5.15.185 | 16 | [Xiaomi_erhu_5.15.185.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_erhu_5.15.185.zip) |
| 红米平板Pro 5G | `ruan` | 5.10.198 | 14 | [Xiaomi_ruan_5.10.198.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_ruan_5.10.198.zip) |
| 红米平板SE | `xun` | 5.15.74 | 13 | [Xiaomi_xun_5.15.74.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_xun_5.15.74.zip) |
| 红米平板SE 8.7 4G | `spark` | 5.10.198 | 12 | [Xiaomi_spark_5.10.198.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_spark_5.10.198.zip) |
| 红米A3 | `blue` | 5.10.177 | 14 | [Xiaomi_blue_5.10.177.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_blue_5.10.177.zip) |
| 红米A4 5G | `warm` | 6.1.68 | 14 | [Xiaomi_warm_6.1.68.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_warm_6.1.68.zip) |
| 红米K20 | `davinci` | 4.14 | 9 | [Redmi_K20_Mi_9T_davinci_4.14.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Redmi_K20_Mi_9T_davinci_4.14.zip) |
| 红米K20 Pro | `raphael` | 4.14 | 9 | [Redmi_K20_Pro_Mi_9T_Pro_raphael_4.14.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Redmi_K20_Pro_Mi_9T_Pro_raphael_4.14.zip) |
| 红米K30 4G | `phoenix` | 4.14.180 | 11 | [Xiaomi_phoenix_4.14.180.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_phoenix_4.14.180.zip) |
| 红米K30 4G | `phoenix` | 4.14.117 | 10 | [Xiaomi_phoenix_4.14.117.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_phoenix_4.14.117.zip) |
| 红米K30 5G | `picasso` | 4.19.113 | 11 | [Xiaomi_picasso_4.19.113.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_picasso_4.19.113.zip) |
| 红米K30 5G | `picasso` | 4.19.81 | 10 | [Xiaomi_picasso_4.19.81.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_picasso_4.19.81.zip) |
| 红米K30 Pro | `lmi` | 4.19 | 10 | [Redmi_K30_Pro_POCO_F2_Pro_lmi_4.19.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Redmi_K30_Pro_POCO_F2_Pro_lmi_4.19.zip) |
| 红米K30 Ultra | `cezanne` | 4.14.186 | 11 | [Xiaomi_cezanne_4.14.186.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_cezanne_4.14.186.zip) |
| 红米K30 Ultra | `cezanne` | 4.14.141 | 10 | [Xiaomi_cezanne_4.14.141.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_cezanne_4.14.141.zip) |
| 红米K30S Ultra | `apollo` | 4.19.81 | 10 | [Xiaomi_apollo_4.19.81.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_apollo_4.19.81.zip) |
| 红米K40 | `alioth` | 4.19 | 11 | [Redmi_K40_POCO_F3_alioth_4.19.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Redmi_K40_POCO_F3_alioth_4.19.zip) |
| 红米K40 电竞版 | `ares` | 4.14.186 | 11 | [Xiaomi_ares_4.14.186.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_ares_4.14.186.zip) |
| 红米K40 Pro | `haydn` | 5.4 | 11 | [Redmi_K40_Pro_K40_Pro_haydn_5.4.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Redmi_K40_Pro_K40_Pro_haydn_5.4.zip) |
| 红米K40S | `munch` | 4.19.157 | 12 | [Xiaomi_munch_4.19.157.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_munch_4.19.157.zip) |
| 红米K50 | `rubens` | 5.10.66 | 12 | [Xiaomi_rubens_5.10.66.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_rubens_5.10.66.zip) |
| 红米K50G | `ingres` | 5.10.43 | 12 | [Xiaomi_ingres_5.10.43.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_ingres_5.10.43.zip) |
| 红米K60 | `mondrian` | 5.10.81 | 12 | [Xiaomi_mondrian_5.10.81.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_mondrian_5.10.81.zip) |
| 红米K60 Pro | `socrates` | 5.15.41 | 13 | [Xiaomi_socrates_5.15.41.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_socrates_5.15.41.zip) |
| 红米K90 | `annibale` | 6.6.57 | 16 | [Xiaomi_annibale_6.6.57.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_annibale_6.6.57.zip) |
| 红米K90 Ultra | `warsaw` | 6.6.57 | 16 | [Xiaomi_warsaw_6.6.57.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_warsaw_6.6.57.zip) |
| 红米Note 6 Pro | `tulip` | 4.4.153 | 9 | [Xiaomi_tulip_4.4.153.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_tulip_4.4.153.zip) |
| 红米Note 7 | `lavender` | 4.4.192 | 10 | [Xiaomi_lavender_4.4.192.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_lavender_4.4.192.zip) |
| 红米Note 7 | `lavender` | 4.4.153 | 9 | [Xiaomi_lavender_4.4.153.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_lavender_4.4.153.zip) |
| 红米Note 7 Pro | `violet` | 4.14.117 | 10 | [Xiaomi_violet_4.14.117.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_violet_4.14.117.zip) |
| 红米Note 7 Pro | `violet` | 4.14.81 | 9 | [Xiaomi_violet_4.14.81.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_violet_4.14.81.zip) |
| 红米Note 8 | `ginkgo` | 4.14 | 10 | [Redmi_Note_8_8T_ginkgo_4.14.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Redmi_Note_8_8T_ginkgo_4.14.zip) |
| 红米Note 8 | `ginkgo` | 4.14.98 | 9 | [Redmi_Note_8_8T_ginkgo_4.14.98.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Redmi_Note_8_8T_ginkgo_4.14.98.zip) |
| 红米Note 8 (2021) | `biloba` | 4.14.186 | 11 | [Xiaomi_biloba_4.14.186.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_biloba_4.14.186.zip) |
| 红米Note 8 Pro | `begonia` | 4.14.186 | 11 | [Xiaomi_begonia_4.14.186.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_begonia_4.14.186.zip) |
| 红米Note 8 Pro | `begonia` | 4.14.141 | 10 | [Xiaomi_begonia_4.14.141.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_begonia_4.14.141.zip) |
| 红米Note 8 Pro | `begonia` | 4.14.94 | 9 | [Xiaomi_begonia_4.14.94.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_begonia_4.14.94.zip) |
| 红米Note 8T | `willow` | 4.14.98 | 9 | [Xiaomi_willow_4.14.98.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_willow_4.14.98.zip) |
| 红米Note 9 4G | `lime` | 4.19.95 | 10 | [Xiaomi_lime_4.19.95.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_lime_4.19.95.zip) |
| 红米Note 9 5G | `cannon` | 4.14.186 | 11 | [Xiaomi_cannon_4.14.186.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_cannon_4.14.186.zip) |
| 红米Note 9 5G | `cannon` | 4.14.141 | 10 | [Xiaomi_cannon_4.14.141.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_cannon_4.14.141.zip) |
| 红米Note 9 Pro 5G | `gauguin` | 4.19.113 | 11 | [Xiaomi_gauguin_4.19.113.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_gauguin_4.19.113.zip) |
| 红米Note 9 Pro 5G | `gauguin` | 4.19.81 | 10 | [Xiaomi_gauguin_4.19.81.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_gauguin_4.19.81.zip) |
| 红米Note 10 5G | `camellian` | 4.14.186 | 13 | [Xiaomi_camellian_4.14.186.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_camellian_4.14.186.zip) |
| 红米Note 10 5G | `camellia` | 4.14.186 | 11 | [Xiaomi_camellia_4.14.186.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_camellia_4.14.186.zip) |
| 红米Note 10 Pro | `sweet` | 4.14 | 11 | [Redmi_Note_10_Pro_sweet_4.14.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Redmi_Note_10_Pro_sweet_4.14.zip) |
| 红米Note 10 Pro 5G | `chopin` | 4.14.186 | 11 | [Xiaomi_chopin_4.14.186.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_chopin_4.14.186.zip) |
| 红米Note 10S | `rosemary` | 4.14.186 | 11 | [Xiaomi_rosemary_4.14.186.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_rosemary_4.14.186.zip) |
| 红米Note 11 | `spes` | 4.19.157 | 11 | [Xiaomi_spes_4.19.157.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_spes_4.19.157.zip) |
| 红米Note 11 5G | `evergo` | 4.14.186 | 11 | [Xiaomi_evergo_4.14.186.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_evergo_4.14.186.zip) |
| 红米Note 11 Pro | `pissarro` | 4.14.186 | 12 | [Xiaomi_pissarro_4.14.186.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_pissarro_4.14.186.zip) |
| 红米Note 11 Pro | `pissarro` | 4.14.186 | 11 | [Xiaomi_pissarro_4.14.186.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_pissarro_4.14.186.zip) |
| 红米Note 11 Pro 4G | `viva` | 4.14.186 | 11 | [Xiaomi_viva_4.14.186.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_viva_4.14.186.zip) |
| 红米Note 11E | `light` | 4.19.191 | 14 | [Xiaomi_light_4.19.191.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_light_4.19.191.zip) |
| 红米Note 11E Pro | `veux` | 5.4 | 11 | [Redmi_Note_11_Pro_5G_POCO_X4_Pro_5G_veux_5.4.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Redmi_Note_11_Pro_5G_POCO_X4_Pro_5G_veux_5.4.zip) |
| 红米Note 11S 4G | `fleur` | 4.14.186 | 12 | [Xiaomi_fleur_4.14.186.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_fleur_4.14.186.zip) |
| 红米Note 11T Pro | `xaga` | 5.10.66 | 12 | [Xiaomi_xaga_5.10.66.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_xaga_5.10.66.zip) |
| 红米Note 12 4G NFC | `topaz` | 5.15.41 | 13 | [Xiaomi_topaz_5.15.41.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_topaz_5.15.41.zip) |
| 红米Note 12 5G | `sunstone` | 5.4.289 | 14 | [Xiaomi_sunstone_5.4.289.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_sunstone_5.4.289.zip) |
| 红米Note 12 Pro | `ruby` | 4.19.191 | 12 | [Xiaomi_ruby_4.19.191.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_ruby_4.19.191.zip) |
| 红米Note 12 Pro 极速版 | `redwood` | 5.4.147 | 12 | [Xiaomi_redwood_5.4.147.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_redwood_5.4.147.zip) |
| 红米Note 12 Turbo | `marble` | 5.10.117 | 12 | [Xiaomi_marble_5.10.117.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_marble_5.10.117.zip) |
| 红米Note 12R | `sky` | 5.10.160 | 13 | [Xiaomi_sky_5.10.160.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_sky_5.10.160.zip) |
| 红米Note 12S | `sea` | 4.19.191 | 13 | [Xiaomi_sea_4.19.191.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_sea_4.19.191.zip) |
| 红米Note 12T Pro | `pearl` | 5.10.136 | 12 | [Xiaomi_pearl_5.10.136.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_pearl_5.10.136.zip) |
| 红米Note 13 5G | `gold` | 5.10.168 | 12 | [Xiaomi_gold_5.10.168.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_gold_5.10.168.zip) |
| 红米Note 13 Pro 5G | `garnet` | 5.10.160 | 13 | [Xiaomi_garnet_5.10.160.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_garnet_5.10.160.zip) |
| 红米Note 13R | `breeze` | 5.10.198 | 14 | [Xiaomi_breeze_5.10.198.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_breeze_5.10.198.zip) |
| 红米Note 15 5G | `kunzite` | 6.6.56 | 15 | [Xiaomi_kunzite_6.6.56.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_kunzite_6.6.56.zip) |
| 红米Note 15 Pro+ 5G | `flourite` | 6.1.68 | 15 | [Xiaomi_flourite_6.1.68.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_flourite_6.1.68.zip) |
| 红米Note 17 4G | `zephyr` | 5.15.185 | 16 | [Xiaomi_zephyr_5.15.185.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_zephyr_5.15.185.zip) |
| 红米Note 17 5G | `mist` | 6.6.118 | 16 | [Xiaomi_mist_6.6.118.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_mist_6.6.118.zip) |
| 红米Turbo 3 | `peridot` | 6.1.57 | 14 | [Xiaomi_peridot_6.1.57.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_peridot_6.1.57.zip) |
| 红米Turbo 4 Pro | `onyx` | 6.6.56 | 15 | [Xiaomi_onyx_6.6.56.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_onyx_6.6.56.zip) |
| 红米Y3 | `onc` | 4.9.186 | 10 | [Xiaomi_onc_4.9.186.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_onc_4.9.186.zip) |
| 红米Y3 | `onc` | 4.9.112 | 9 | [Xiaomi_onc_4.9.112.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_onc_4.9.112.zip) |
| 通用 GKI | `gki-a12` | 5.10 | 12 | [Google_Android_12_gki-a12_5.10.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Google_Android_12_gki-a12_5.10.zip) |
| 通用 GKI | `gki-a13` | 5.15 | 13 | [Google_Android_13_gki-a13_5.15.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Google_Android_13_gki-a13_5.15.zip) |
| 通用 GKI | `gki-a14` | 6.1 | 14 | [Google_Android_14_gki-a14_6.1.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Google_Android_14_gki-a14_6.1.zip) |
| 通用 GKI | `gki-a15` | 6.6 | 15 | [Google_Android_15_gki-a15_6.6.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Google_Android_15_gki-a15_6.6.zip) |
| 通用 GKI | `gki-a16` | 6.12 | 16 | [Google_Android_16_gki-a16_6.12.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Google_Android_16_gki-a16_6.12.zip) |
| 小米6 | `sagit` | 4.4.153 | 9 | [Xiaomi_sagit_4.4.153.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_sagit_4.4.153.zip) |
| 小米8 | `dipper` | 4.9.186 | 10 | [Xiaomi_dipper_4.9.186.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_dipper_4.9.186.zip) |
| 小米8 | `dipper` | 4.9.112 | 9 | [Xiaomi_dipper_4.9.112.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_dipper_4.9.112.zip) |
| 小米8 SE | `sirius` | 4.9.186 | 10 | [Xiaomi_sirius_4.9.186.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_sirius_4.9.186.zip) |
| 小米9 SE | `grus` | 4.9.112 | 9 | [Xiaomi_grus_4.9.112.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_grus_4.9.112.zip) |
| 小米10 | `umi` | 4.19 | 10 | [Xiaomi_10_Mi_10_Pro_umi_4.19.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_10_Mi_10_Pro_umi_4.19.zip) |
| 小米10 Lite Zoom | `vangogh` | 4.19.81 | 10 | [Xiaomi_vangogh_4.19.81.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_vangogh_4.19.81.zip) |
| 小米10 Pro | `cmi` | 4.19.113 | 11 | [Xiaomi_cmi_4.19.113.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_cmi_4.19.113.zip) |
| 小米10 Ultra | `cas` | 4.19.81 | 10 | [Xiaomi_cas_4.19.81.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_cas_4.19.81.zip) |
| 小米11 | `venus` | 5.4 | 11 | [Xiaomi_11_venus_5.4.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_11_venus_5.4.zip) |
| 小米11 LE | `lisa` | 5.4.86 | 11 | [Xiaomi_lisa_5.4.86.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_lisa_5.4.86.zip) |
| 小米11 Lite 4G | `courbet` | 4.14.180 | 11 | [Xiaomi_courbet_4.14.180.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_courbet_4.14.180.zip) |
| 小米11 Pro | `star` | 5.4.61 | 11 | [Xiaomi_star_5.4.61.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_star_5.4.61.zip) |
| 小米11T | `agate` | 4.19.191 | 14 | [Xiaomi_agate_4.19.191.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_agate_4.19.191.zip) |
| 小米11T Pro | `vili` | 5.4.86 | 11 | [Xiaomi_vili_5.4.86.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_vili_5.4.86.zip) |
| 小米12 Lite | `taoyao` | 5.4.86 | 12 | [Xiaomi_taoyao_5.4.86.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_taoyao_5.4.86.zip) |
| 小米12 Pro | `zeus` | 5.10.43 | 12 | [Xiaomi_zeus_5.10.43.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_zeus_5.10.43.zip) |
| 小米12 Pro Dimensity | `daumier` | 5.10.81 | 12 | [Xiaomi_daumier_5.10.81.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_daumier_5.10.81.zip) |
| 小米12S | `mayfly` | 5.10.81 | 12 | [Xiaomi_mayfly_5.10.81.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_mayfly_5.10.81.zip) |
| 小米12X | `psyche` | 4.19.113 | 11 | [Xiaomi_psyche_4.19.113.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_psyche_4.19.113.zip) |
| 小米13 | `fuxi` | 5.15.41 | 13 | [Xiaomi_fuxi_5.15.41.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_fuxi_5.15.41.zip) |
| 小米13 Ultra | `ishtar` | 5.15.41 | 13 | [Xiaomi_ishtar_5.15.41.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_ishtar_5.15.41.zip) |
| 小米14 Pro | `shennong` | 6.1.25 | 14 | [Xiaomi_shennong_6.1.25.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_shennong_6.1.25.zip) |
| 小米14 Ultra | `aurora` | 6.1.25 | 14 | [Xiaomi_aurora_6.1.25.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_aurora_6.1.25.zip) |
| 小米15 | `dada` | 6.6.30 | 15 | [Xiaomi_dada_6.6.30.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_dada_6.6.30.zip) |
| 小米15 Ultra | `xuanyuan` | 6.6.30 | 15 | [Xiaomi_xuanyuan_6.6.30.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_xuanyuan_6.6.30.zip) |
| 小米平板5 Pro 12.4 | `dagu` | 4.19.157 | 12 | [Xiaomi_dagu_4.19.157.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_dagu_4.19.157.zip) |
| 小米平板5 Pro Wi-Fi | `elish` | 4.19.113 | 11 | [Xiaomi_elish_4.19.113.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_elish_4.19.113.zip) |
| 小米平板6 | `pipa` | 4.19.157 | 13 | [Xiaomi_pipa_4.19.157.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_pipa_4.19.157.zip) |
| 小米平板6 Max 14 | `yudi` | 5.10.160 | 13 | [Xiaomi_yudi_5.10.160.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_yudi_5.10.160.zip) |
| 小米平板6 Pro | `liuqin` | 5.10.81 | 13 | [Xiaomi_liuqin_5.10.81.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_liuqin_5.10.81.zip) |
| 小米平板6S Pro 12.4 | `sheng` | 5.15.78 | 14 | [Xiaomi_sheng_5.15.78.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_sheng_5.15.78.zip) |
| 小米平板7 | `uke` | 6.1.68 | 15 | [Xiaomi_uke_6.1.68.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_uke_6.1.68.zip) |
| 小米平板7 Pro | `muyu` | 6.1.68 | 15 | [Xiaomi_muyu_6.1.68.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_muyu_6.1.68.zip) |
| 小米平板8 | `yupei` | 6.6.57 | 16 | [Xiaomi_yupei_6.6.57.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_yupei_6.6.57.zip) |
| 小米平板8 Pro | `piano` | 6.6.57 | 16 | [Xiaomi_piano_6.6.57.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_piano_6.6.57.zip) |
| 小米A2 | `jasmine` | 4.4.192 | 10 | [Xiaomi_jasmine_4.4.192.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_jasmine_4.4.192.zip) |
| 小米A2 | `jasmine` | 4.4.153 | 9 | [Xiaomi_jasmine_4.4.153.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_jasmine_4.4.153.zip) |
| 小米A3 | `laurel` | 4.14.180 | 11 | [Xiaomi_laurel_4.14.180.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_laurel_4.14.180.zip) |
| 小米A3 | `laurel` | 4.14.117 | 10 | [Xiaomi_laurel_4.14.117.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_laurel_4.14.117.zip) |
| 小米CC9 | `pyxis` | 4.9.112 | 9 | [Xiaomi_pyxis_4.9.112.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_pyxis_4.9.112.zip) |
| 小米CC9 Pro | `tucana` | 4.14.117 | 10 | [Xiaomi_tucana_4.14.117.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_tucana_4.14.117.zip) |
| 小米CC9 Pro | `tucana` | 4.14.83 | 9 | [Xiaomi_tucana_4.14.83.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_tucana_4.14.83.zip) |
| 小米CC9e | `laurus` | 4.14.117 | 10 | [Xiaomi_laurus_4.14.117.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_laurus_4.14.117.zip) |
| 小米CC9e | `laurus` | 4.14.98 | 9 | [Xiaomi_laurus_4.14.98.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_laurus_4.14.98.zip) |
| 小米Civi | `mona` | 5.4.86 | 11 | [Xiaomi_mona_5.4.86.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_mona_5.4.86.zip) |
| 小米Civi 1S | `zijin` | 5.4.86 | 12 | [Xiaomi_zijin_5.4.86.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_zijin_5.4.86.zip) |
| 小米Civi 2 | `ziyi` | 5.10.81 | 12 | [Xiaomi_ziyi_5.10.81.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_ziyi_5.10.81.zip) |
| 小米Civi 3 | `yuechu` | 5.10.136 | 13 | [Xiaomi_yuechu_5.10.136.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_yuechu_5.10.136.zip) |
| 小米Civi 4 Pro | `chenfeng` | 6.1.57 | 14 | [Xiaomi_chenfeng_6.1.57.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_chenfeng_6.1.57.zip) |
| 小米Max 3 | `nitrogen` | 4.4.192 | 10 | [Xiaomi_nitrogen_4.4.192.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_nitrogen_4.4.192.zip) |
| 小米Max 3 | `nitrogen` | 4.4.153 | 9 | [Xiaomi_nitrogen_4.4.153.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_nitrogen_4.4.153.zip) |
| 小米MIX 3 | `perseus` | 4.9.112 | 9 | [Xiaomi_perseus_4.9.112.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_perseus_4.9.112.zip) |
| 小米MIX 4 | `odin` | 5.4.86 | 11 | [Xiaomi_odin_5.4.86.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_odin_5.4.86.zip) |
| 小米MIX Flip 2 | `bixi` | 6.6.56 | 15 | [Xiaomi_bixi_6.6.56.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_bixi_6.6.56.zip) |
| 小米Note 3 | `jason` | 4.4.153 | 9 | [Xiaomi_jason_4.4.153.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_jason_4.4.153.zip) |
| 小米Note 10 Lite | `toco` | 4.14.117 | 10 | [Xiaomi_toco_4.14.117.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_toco_4.14.117.zip) |
| 一加 7 Pro | `op7pro` | 4.14 | 9 | [OnePlus_7_7_Pro_7T_7T_Pro_op7pro_4.14.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/OnePlus_7_7_Pro_7T_7T_Pro_op7pro_4.14.zip) |
| 一加 7 Pro | `op7pro` | 4.14 | 10 | [OnePlus_7_7_Pro_7T_7T_Pro_op7pro_4.14.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/OnePlus_7_7_Pro_7T_7T_Pro_op7pro_4.14.zip) |
| 一加 7 Pro | `op7pro` | 4.14 | 12 | [OnePlus_7_7_Pro_7T_7T_Pro_op7pro_4.14.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/OnePlus_7_7_Pro_7T_7T_Pro_op7pro_4.14.zip) |
| 一加 8 | `op8` | 4.19 | 10 | [OnePlus_8_8_Pro_op8_4.19.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/OnePlus_8_8_Pro_op8_4.19.zip) |
| 一加 8 | `op8` | 4.19 | 11 | [OnePlus_8_8_Pro_op8_4.19.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/OnePlus_8_8_Pro_op8_4.19.zip) |
| 一加 8 | `op8` | 4.19 | 13 | [OnePlus_8_8_Pro_op8_4.19.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/OnePlus_8_8_Pro_op8_4.19.zip) |
| 一加 8T | `op8t` | 4.19 | 11 | [OnePlus_8T_9R_op8t_4.19.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/OnePlus_8T_9R_op8t_4.19.zip) |
| 一加 8T | `op8t` | 4.19 | 12 | [OnePlus_8T_9R_op8t_4.19.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/OnePlus_8T_9R_op8t_4.19.zip) |
| 一加 8T | `op8t` | 4.19 | 13 | [OnePlus_8T_9R_op8t_4.19.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/OnePlus_8T_9R_op8t_4.19.zip) |
| 一加 8T | `op8t` | 4.19 | 14 | [OnePlus_8T_9R_op8t_4.19.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/OnePlus_8T_9R_op8t_4.19.zip) |
| 一加 9 | `op9` | 5.4 | 11 | [OnePlus_9_9_Pro_op9_5.4.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/OnePlus_9_9_Pro_op9_5.4.zip) |
| 一加 9 | `op9` | 5.4 | 12 | [OnePlus_9_9_Pro_op9_5.4.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/OnePlus_9_9_Pro_op9_5.4.zip) |
| 一加 9 | `op9` | 5.15 | 13 | [OnePlus_9_9_Pro_op9_5.15.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/OnePlus_9_9_Pro_op9_5.15.zip) |
| 一加 9 | `op9` | 5.15 | 14 | [OnePlus_9_9_Pro_op9_5.15.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/OnePlus_9_9_Pro_op9_5.15.zip) |
| 一加 9RT | `op9rt` | 5.4 | 11 | [OnePlus_9RT_op9rt_5.4.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/OnePlus_9RT_op9rt_5.4.zip) |
| 一加 9RT | `op9rt` | 5.15 | 13 | [OnePlus_9RT_op9rt_5.15.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/OnePlus_9RT_op9rt_5.15.zip) |
| POCO X3 NFC | `surya` | 4.14 | 10 | [POCO_X3_NFC_surya_4.14.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/POCO_X3_NFC_surya_4.14.zip) |
| POCO X5 5G | `moonstone` | 5.4.191 | 12 | [Xiaomi_moonstone_5.4.191.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_moonstone_5.4.191.zip) |
| POCO X8s | `darwin` | 6.6.57 | 16 | [Xiaomi_darwin_6.6.57.zip](https://github.com/xingyiqaq/sukisu-kernel-builder/releases/download/%E5%86%85%E6%A0%B8%E5%90%88%E9%9B%86/Xiaomi_darwin_6.6.57.zip) |
<!-- KERNEL-INDEX:END -->
