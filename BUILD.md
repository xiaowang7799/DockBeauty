# 编译与安装（在 macOS + Theos 环境，不在 Windows）

本工程由 `axs-ios-tweaks` 脚手架生成，并做了 Dock 美化扩展。本机只做了静态检查
（`scripts/doctor.py` 通过），**没有真实编译过**。

## 前置
- macOS，已装 [Theos](https://theos.dev/)，且 `THEOS` 环境变量指向它。
- iOS SDK（本工程统一 `16.5`，见 `AxsDockBeautyBuild.mk` 的 `TARGET`）。
- 目标机已越狱，装了 `mobilesubstrate` + `preferenceloader`（control 已声明依赖）。

## 构建
```sh
cd DockBeauty
make clean
make package FINALPACKAGE=1        # 生成 .deb 到 ./packages
```

## 安装到设备
```sh
# 方式一：Theos 直连（设备开了 OpenSSH）
make install

# 方式二：手动拷贝 deb 后用包管理器
scp packages/*.deb root@<设备IP>:/tmp/
ssh root@<设备IP> 'dpkg -i /tmp/*.deb && killall backboardd'   # 或 uicache + 注销
```
PreferenceLoader 面板路径：`/Library/PreferenceLoader/Preferences/`，
Bundle 安装到 `/Library/PreferenceBundles/`，无需手动处理。

## 启用
设置 → Dock美化 → 打开「启用插件」。动效在 SpringBoard 启动后约 2 秒挂载。

## 已知需真机验证的点
- 壁纸取色用的是私有类 `SBFWallpaperView` / `currentWallpaperImage`，名称随 iOS 版本可能变化；
  取不到时自动回退到你手设的色相，不会崩。
- Dock 视图按 `*DockView` 类名后缀匹配，个别 iOS 版本若改名需补。
- 气泡粒子 / 流光为轻量 demo 级实现，真机渲染效果未验证。
