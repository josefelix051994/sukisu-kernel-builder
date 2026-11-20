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
| `--gki` | 标记为 GKI 通用内核(默认 LKM 模式) |
| `--ksu <main\|builtin>` | SukiSU 集成分支(默认: GKI 设备=main, 传统内核=builtin) |
| `--ksu-mode <y\|m>` | `y`=内置(非 GKI 默认),`m`=LKM 模块(GKI 默认;builtin 分支只支持 y) |
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

- `GKI标志`:`1` = GKI 通用内核(默认 LKM 模式),`0` = 非 GKI(默认内置模式)
- `defconfig提示` 可留空(自动按设备 ID 探测),支持 glob(如 `vendor/kona*`)
- **片段配置**(`vendor/*_consolidate.config`、`*_GKI.config` 等不足 200 行的文件):工具会自动以 `gki_defconfig` 为基础合并片段,并裁掉 FULL LTO / KASAN / DWARF 等调试选项(否则 2 核 runner 极易超时)
- 改完 `devices.conf` 后请重新生成两份派生文件:

```bash
bash gen_devices.sh > devices.json      # 网页用的设备清单
bash tools/gen_build_scripts.sh         # 每机型每版本的独立编译脚本(builds/)
```

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
| LKM(`CONFIG_KSU=m`,GKI 默认) | 如 `Google_Android_15_gki-a15_6.6_SukiSU-v3.0.0_20261120-2003.ko` | SukiSU 管理器 → 安装 → **使用本地 LKM 文件**(仅支持 `.ko`) |

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
| 4.19 | ✅ 通过(全类) | `dtc` 的 `yylloc` 重复定义、`KPROBES/EXT4_FS` 依赖、`-Wno-error`(厂商 `subdir-ccflags -Werror` 直接剥离) |
| 4.14 | ✅ 通过(davinci/begonia) | GCC4.9 binutils 符号链接(`aarch64-linux-gnu-ld` 支持 `-pie -shared` 链接)、`kvcalloc`、vdso 宏前导逗号、`_shipped` dtc 源码补丁 |
| 4.9 / 4.4 | ✅ 通过(jasmine/dandelion) | `sched/signal.h`→`sched.h`(4.11 前无拆分头)、KPM 自动关闭(4.14 以下不支持)、`fallthrough` 宏、`MIN/MAX` 头 |
| 3.18 | ❌ 不支持 | SukiSU-Ultra builtin 最低要求 Linux 4.4+(3.x 会在预检阶段快速失败并给出明确提示);网页上这类版本标注「⚠ 不支持」,只能演练 |

**厂商源码不完整导致的失败(非工具问题)**:小米开源树存在未公开的目录/文件,工具会尽量自动修补(注释缺失的 `source`/`obj-y` 条目、缺失闭源固件 `.i` 自动写占位字节、平台 HAL 目录按 `CONFIG_MTK_PLATFORM` 正确下钻),但少数机型仍可能因为厂商驱动缺失而链接失败。常见类别与代表机型:

| 类别 | 典型报错 | 代表机型 |
|---|---|---|
| 平台 HAL/符号未公开 | `undefined reference to 'mt_set_pwm_clk_hal'` 等 MTK 平台 HAL | 个别 MTK 4.14 树 |
| 私有头文件缺失 | `fatal error: 'hwid.h' file not found` | flourite(6.1.68) |
| 依赖驱动未启用 | `undefined reference to 'mi_disp_register_client'` | lisa(5.4.86) |
| 厂商源码自身 bug | `use of undeclared identifier 'curve_prime'`(crypto/ecc.c) | breeze(5.10.198) |
| 重复符号定义 | `ld.lld: error: duplicate symbol: __SCK__tp_func_*` | erhu/fuxi(5.15) |
| 老 Makefile 与 GNU make 4.x 不兼容 | `prerequisites cannot be defined in recipes` | dipper(4.9.112) |

这类设备编译失败时,步骤日志末尾的「日志中的错误行(最后 8 条)」会直接给出失败原因;产物上传/发布步骤会被标记为「已跳过」。

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

### 9.4 自动发布 Release

`build.yml` 支持 **编译成功后自动创建 GitHub Release**(网页「高级选项 → 自动发布到 Release」,默认勾选;命令行用 `build-all.yml` 的 `publish` 输入):

- Release tag 形如 `build-Redmi_K40+POCO_F3_alioth_4.19.113_SukiSU-v3.0.0_20261120-2003`,标题即产物名;
- 正文由 `output/release-notes.md` 生成,包含品牌/机型、机型代码、内核版本、内核源码分支、SukiSU 版本与集成分支、CONFIG_KSU 模式、编译时间,以及对应的刷入步骤和免责声明;
- 附件即编译产物(zip / .ko),可直接从 Releases 页面下载,不受 artifact 14 天过期限制;
- 全量编译默认不发布(避免一次生成上百个 Release),需要时给 `build-all.yml` 传 `publish: true`。

## 免责声明

本工具仅供学习与个人设备使用,编译、刷入内核存在风险,可能造成数据丢失或设备变砖,请自行承担。SukiSU-Ultra、AnyKernel3、各内核源码版权归各自作者所有。
