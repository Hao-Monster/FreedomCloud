; *** Inno Setup 简体中文语言文件 (FreedomNet) ***

[LangOptions]
LanguageName=<7B80><4F53><4E2D><6587>
LanguageID=$0804
LanguageCodePage=936
DialogFontName=Microsoft YaHei UI
DialogFontSize=9
WelcomeFontName=Microsoft YaHei UI
WelcomeFontSize=12
TitleFontName=Microsoft YaHei UI
TitleFontSize=29
CopyrightFontName=Microsoft YaHei UI
CopyrightFontSize=9

[Messages]

; *** 应用程序标题
SetupAppTitle=安装
SetupWindowTitle=安装 - %1
UninstallAppTitle=卸载
UninstallAppFullTitle=卸载 %1

; *** 通用对话框标题
InformationTitle=信息
ConfirmTitle=确认
ErrorTitle=错误

; *** SetupLdr 启动消息
SetupLdrStartupMessage=即将在您的电脑上安装 %1。是否继续？
LdrCannotCreateTemp=无法创建临时文件，安装已中止
LdrCannotExecTemp=无法在临时目录中执行文件，安装已中止
HelpTextNote=

; *** 启动错误消息
LastErrorMessage=%1.%n%n错误 %2: %3
SetupFileMissing=安装目录中缺少文件 %1。请修正问题或获取程序的全新副本
SetupFileCorrupt=安装文件已损坏。请获取程序的全新副本
SetupFileCorruptOrWrongVer=安装文件已损坏或与此版本的安装程序不兼容。请修正问题或获取程序的全新副本
InvalidParameter=命令行中包含无效参数:%n%n%1
SetupAlreadyRunning=安装程序已在运行中
WindowsVersionNotSupported=本程序不支持您电脑上当前运行的 Windows 版本
WindowsServicePackRequired=本程序需要 %1 Service Pack %2 或更高版本
NotOnThisPlatform=本程序无法在 %1 上运行
OnlyOnThisPlatform=本程序必须在 %1 上运行
OnlyOnTheseArchitectures=本程序仅支持安装在针对以下处理器架构设计的 Windows 版本上:%n%n%1
WinVersionTooLowError=本程序需要 %1 版本 %2 或更高版本
WinVersionTooHighError=本程序无法安装在 %1 版本 %2 或更高版本上
AdminPrivilegesRequired=安装此程序需要以管理员身份登录系统
PowerUserPrivilegesRequired=安装此程序需要以管理员或 Power Users 组成员身份登录系统
SetupAppRunningError=安装程序检测到 %1 正在运行。%n%n请先关闭该程序的所有实例，然后点击“确定”继续，或点击“取消”退出
UninstallAppRunningError=卸载程序检测到 %1 正在运行。%n%n请先关闭该程序的所有实例，然后点击“确定”继续，或点击“取消”退出

; *** 启动权限选择
PrivilegesRequiredOverrideTitle=选择安装模式
PrivilegesRequiredOverrideInstruction=请选择安装模式
PrivilegesRequiredOverrideText1=%1 可以为所有用户安装（需要管理员权限），或仅为您当前用户安装
PrivilegesRequiredOverrideText2=%1 可以仅为您当前用户安装，或为所有用户安装（需要管理员权限）
PrivilegesRequiredOverrideAllUsers=为所有用户安装(&A)
PrivilegesRequiredOverrideAllUsersRecommended=为所有用户安装(&A)（推荐）
PrivilegesRequiredOverrideCurrentUser=仅为我安装(&M)
PrivilegesRequiredOverrideCurrentUserRecommended=仅为我安装(&M)（推荐）

; *** 其他启动错误
ErrorCreatingDir=安装程序无法创建目录“%1”
ErrorTooManyFilesInDir=由于目录“%1”包含过多文件，无法在其中创建文件

; *** 安装程序通用消息
ExitSetupTitle=退出安装程序
ExitSetupMessage=安装尚未完成。如果现在退出，程序将不会被安装。%n%n您可以稍后再次运行安装程序以完成安装。%n%n确定要退出安装程序吗？
AboutSetupMenuItem=关于安装程序(&A)...
AboutSetupTitle=关于安装程序
AboutSetupMessage=%1 版本 %2%n%3%n%n%1 主页:%n%4
AboutSetupNote=
TranslatorNote=简体中文语言包 (FreedomNet)

; *** 按钮文本
ButtonBack=< 上一步(&B)
ButtonNext=下一步(&N) >
ButtonInstall=安装(&I)
ButtonOK=确定
ButtonCancel=取消
ButtonYes=是(&Y)
ButtonYesToAll=全是(&A)
ButtonNo=否(&N)
ButtonNoToAll=全否(&O)
ButtonFinish=完成(&F)
ButtonBrowse=浏览(&B)...
ButtonWizardBrowse=浏览(&R)...
ButtonNewFolder=新建文件夹(&M)

; *** 选择语言对话框
SelectLanguageTitle=选择安装语言
SelectLanguageLabel=请选择安装过程中使用的语言

; *** 向导通用文本
ClickNext=点击“下一步”继续，或点击“取消”退出安装程序
BeveledLabel=
BrowseDialogTitle=选择文件夹
BrowseDialogLabel=请在下方列表中选择文件夹，然后点击“确定”
NewFolderName=新建文件夹

; *** “欢迎”向导页
WelcomeLabel1=欢迎使用 [name] 安装向导
WelcomeLabel2=即将在您的电脑上安装 [name/ver]。%n%n建议在继续前关闭所有其他应用程序

; *** “密码”向导页
WizardPassword=密码
PasswordLabel1=此安装受密码保护
PasswordLabel3=请输入密码，然后点击“下一步”继续。密码区分大小写
PasswordEditLabel=密码(&P):
IncorrectPassword=您输入的密码不正确，请重试

; *** “许可协议”向导页
WizardLicense=许可协议
LicenseLabel=请在继续前阅读以下重要信息
LicenseLabel3=请阅读以下许可协议。您必须接受本协议条款才能继续安装
LicenseAccepted=我接受此协议(&A)
LicenseNotAccepted=我不接受此协议(&D)

; *** “信息”向导页
WizardInfoBefore=信息
InfoBeforeLabel=请在继续前阅读以下重要信息
InfoBeforeClickLabel=准备好继续安装后，请点击“下一步”
WizardInfoAfter=信息
InfoAfterLabel=请在继续前阅读以下重要信息
InfoAfterClickLabel=准备好继续安装后，请点击“下一步”

; *** “用户信息”向导页
WizardUserInfo=用户信息
UserInfoDesc=请输入您的信息
UserInfoName=用户名(&N):
UserInfoOrg=组织(&O):
UserInfoSerial=序列号(&S):
UserInfoNameRequired=您必须输入名称

; *** “选择目标位置”向导页
WizardSelectDir=选择目标位置
SelectDirDesc=应将 [name] 安装到哪里？
SelectDirLabel3=安装程序将把 [name] 安装到以下文件夹中
SelectDirBrowseLabel=要继续，请点击“下一步”。如果您想选择其他文件夹，请点击“浏览”
DiskSpaceGBLabel=至少需要 [gb] GB 的可用磁盘空间
DiskSpaceMBLabel=至少需要 [mb] MB 的可用磁盘空间
CannotInstallToNetworkDrive=安装程序无法安装到网络驱动器
CannotInstallToUNCPath=安装程序无法安装到 UNC 路径
InvalidPath=您必须输入包含盘符的完整路径；例如:%n%nC:\APP%n%n或格式如下的 UNC 路径:%n%n\\server\share
InvalidDrive=您选择的驱动器或 UNC 共享不存在或不可访问，请选择其他位置
DiskSpaceWarningTitle=磁盘空间不足
DiskSpaceWarning=安装至少需要 %1 KB 可用空间，但所选磁盘仅有 %2 KB 可用。%n%n确定要强行继续吗？
DirNameTooLong=文件夹名称或路径过长
InvalidDirName=文件夹名称无效
BadDirName32=文件夹名称不能包含以下任何字符:%n%n%1
DirExistsTitle=文件夹已存在
DirExists=文件夹:%n%n%1%n%n已存在。您仍要安装到此文件夹中吗？
DirDoesntExistTitle=文件夹不存在
DirDoesntExist=文件夹:%n%n%1%n%n不存在。您想创建该文件夹吗？

; *** “选择组件”向导页
WizardSelectComponents=选择组件
SelectComponentsDesc=要安装哪些组件？
SelectComponentsLabel2=选择您要安装的组件；清除不需要安装的组件复选框。准备好继续后点击“下一步”
FullInstallation=完整安装
CompactInstallation=精简安装
CustomInstallation=自定义安装
NoUninstallWarningTitle=组件已存在
NoUninstallWarning=安装程序检测到您的电脑上已安装以下组件:%n%n%1%n%n取消选择这些组件并不会将其卸载。%n%n您仍想继续吗？
ComponentSize1=%1 KB
ComponentSize2=%1 MB
ComponentsDiskSpaceGBLabel=当前选择至少需要 [gb] GB 磁盘空间
ComponentsDiskSpaceMBLabel=当前选择至少需要 [mb] MB 磁盘空间

; *** “选择附加任务”向导页
WizardSelectTasks=选择附加任务
SelectTasksDesc=要执行哪些附加任务？
SelectTasksLabel2=选择安装 [name] 时应执行的附加任务，然后点击“下一步”

; *** “选择开始菜单文件夹”向导页
WizardSelectProgramGroup=选择开始菜单文件夹
SelectStartMenuFolderDesc=安装程序应在何处创建程序快捷方式？
SelectStartMenuFolderLabel3=安装程序将在以下“开始”菜单文件夹中创建程序快捷方式
SelectStartMenuFolderBrowseLabel=点击“下一步”继续。如果要选择其他文件夹，请点击“浏览”
MustEnterGroupName=您必须输入文件夹名称
GroupNameTooLong=文件夹名称或路径过长
InvalidGroupName=文件夹名称无效
BadGroupName=文件夹名称不能包含以下任何字符:%n%n%1
NoProgramGroupCheck2=不创建开始菜单文件夹(&D)

; *** “准备安装”向导页
WizardReady=准备安装
ReadyLabel1=安装程序现已准备好在您的电脑上安装 [name]
ReadyLabel2a=点击“安装”开始安装，如果您想查看或更改任何设置，请点击“上一步”
ReadyLabel2b=点击“安装”开始安装
ReadyMemoUserInfo=用户信息:
ReadyMemoDir=目标位置:
ReadyMemoType=安装类型:
ReadyMemoComponents=已选组件:
ReadyMemoGroup=开始菜单文件夹:
ReadyMemoTasks=附加任务:

; *** 下载向导页
DownloadingLabel=正在下载附加文件...
ButtonStopDownload=停止下载(&S)
StopDownload=您确定要停止下载吗？
ErrorDownloadAborted=下载已中止
ErrorDownloadFailed=下载失败: %1 %2
ErrorDownloadSizeFailed=获取大小失败: %1 %2
ErrorFileHash1=文件哈希校验失败: %1
ErrorFileHash2=文件哈希无效: 预期 %1，实际 %2
ErrorProgress=进度无效: %1 / %2
ErrorFileSize=文件大小无效: 预期 %1，实际 %2

; *** “正在准备安装”向导页
WizardPreparing=正在准备安装
PreparingDesc=安装程序正在准备将 [name] 安装到您的电脑上
PreviousInstallNotCompleted=先前的安装/卸载尚未完成。您需要重启电脑才能完成安装。%n%n重启电脑后，请再次运行安装程序以完成 [name] 的安装
CannotContinue=安装程序无法继续。请点击“取消”退出
ApplicationsFound=以下应用程序正在使用安装程序需要更新的文件。建议允许安装程序自动关闭这些应用程序
ApplicationsFound2=以下应用程序正在使用安装程序需要更新的文件。建议允许安装程序自动关闭这些应用程序。安装完成后，安装程序将尝试重新启动这些应用程序
CloseApplications=自动关闭应用程序(&A)
DontCloseApplications=不关闭应用程序(&D)
ErrorCloseApplications=安装程序无法自动关闭所有应用程序。建议您在继续前手动关闭所有正在使用需要更新文件的应用程序
PrepareToInstallNeedsRestart=安装程序需要重启您的电脑。重启电脑后，请再次运行安装程序以完成 [name] 的安装。%n%n您想现在重启吗？

; *** “正在安装”向导页
WizardInstalling=正在安装
InstallingLabel=请等待安装程序将 [name] 安装到您的电脑上

; *** “安装完成”向导页
FinishedHeadingLabel=[name] 安装向导已完成
FinishedLabelNoIcons=安装程序已在您的电脑上完成 [name] 的安装
FinishedLabel=安装程序已在您的电脑上完成 [name] 的安装。您可以通过所安装的快捷方式启动此应用程序
ClickFinish=点击“完成”退出安装程序
FinishedRestartLabel=要完成 [name] 的安装，安装程序必须重启您的电脑。您想现在重启吗？
FinishedRestartMessage=要完成 [name] 的安装，安装程序必须重启您的电脑。%n%n您想现在重启吗？
ShowReadmeCheck=是，查看自述文件
YesRadio=是，立即重启电脑(&Y)
NoRadio=否，稍后手动重启电脑(&N)
RunEntryExec=运行 %1
RunEntryShellExec=查看 %1

; *** “安装程序需要下一张磁盘”消息
ChangeDiskTitle=安装程序需要下一张磁盘
SelectDiskLabel2=请插入磁盘 %1 并点击“确定”。%n%n如果该磁盘中的文件位于下方所示以外的文件夹中，请输入正确路径或点击“浏览”
PathLabel=路径(&P):
FileNotInDir2=在“%2”中找不到文件“%1”。请插入正确的磁盘或选择其他文件夹
SelectDirectoryLabel=请指定下一张磁盘的位置

; *** 安装状态消息
SetupAborted=安装尚未完成。%n%n请修正问题并重新运行安装程序
AbortRetryIgnoreSelectAction=选择操作
AbortRetryIgnoreRetry=重试(&R)
AbortRetryIgnoreIgnore=忽略错误并继续(&I)
AbortRetryIgnoreCancel=取消安装

; *** 安装阶段状态文本
StatusClosingApplications=正在关闭应用程序...
StatusCreateDirs=正在创建目录...
StatusExtractFiles=正在提取文件...
StatusCreateIcons=正在创建快捷方式...
StatusCreateIniEntries=正在创建 INI 项...
StatusCreateRegistryEntries=正在创建注册表项...
StatusRegisterFiles=正在注册文件...
StatusSavingUninstall=正在保存卸载信息...
StatusRunProgram=正在完成安装...
StatusRestartingApplications=正在重新启动应用程序...
StatusRollback=正在回滚更改...

; *** 其他错误
ErrorInternal2=内部错误: %1
ErrorFunctionFailedNoCode=%1 失败
ErrorFunctionFailed=%1 失败；代码 %2
ErrorFunctionFailedWithMessage=%1 失败；代码 %2.%n%3
ErrorExecutingProgram=无法执行文件:%n%1

; *** 注册表错误
ErrorRegOpenKey=打开注册表项出错:%n%1\%2
ErrorRegCreateKey=创建注册表项出错:%n%1\%2
ErrorRegWriteKey=写入注册表项出错:%n%1\%2

; *** INI 错误
ErrorIniEntry=在文件“%1”中创建 INI 项出错

; *** 文件复制错误
FileAbortRetryIgnoreSkipNotRecommended=跳过此文件（不推荐）(&S)
FileAbortRetryIgnoreIgnoreNotRecommended=忽略错误并继续（不推荐）(&I)
SourceIsCorrupted=源文件已损坏
SourceDoesntExist=源文件“%1”不存在
ExistingFileReadOnly2=无法替换现有文件，因为其带有只读属性
ExistingFileReadOnlyRetry=清除只读属性并重试(&R)
ExistingFileReadOnlyKeepExisting=保留现有文件(&K)
ErrorReadingExistingDest=尝试读取现有文件时发生错误:
FileExistsSelectAction=选择操作
FileExists2=文件已存在
FileExistsOverwriteExisting=覆盖现有文件(&O)
FileExistsKeepExisting=保留现有文件(&K)
FileExistsOverwriteOrKeepAll=为接下来的所有冲突执行此操作(&D)
ExistingFileNewerSelectAction=选择操作
ExistingFileNewer2=现有文件比安装程序尝试安装的文件更新
ExistingFileNewerOverwriteExisting=覆盖现有文件(&O)
ExistingFileNewerKeepExisting=保留现有文件（推荐）(&K)
ExistingFileNewerOverwriteOrKeepAll=为接下来的所有冲突执行此操作(&D)
ErrorChangingAttr=尝试更改现有文件属性时发生错误:
ErrorCreatingTemp=尝试在目标目录创建文件时发生错误:
ErrorReadingSource=尝试读取源文件时发生错误:
ErrorCopying=尝试复制文件时发生错误:
ErrorReplacingExistingFile=尝试替换现有文件时发生错误:
ErrorRestartReplace=重启替换失败:
ErrorRenamingTemp=尝试在目标目录重命名文件时发生错误:
ErrorRegisterServer=无法注册 DLL/OCX: %1
ErrorRegSvr32Failed=RegSvr32 失败，退出代码 %1
ErrorRegisterTypeLib=无法注册类型库: %1

; *** 卸载显示名称标记
UninstallDisplayNameMark=%1 (%2)
UninstallDisplayNameMarks=%1 (%2, %3)
UninstallDisplayNameMark32Bit=32 位
UninstallDisplayNameMark64Bit=64 位
UninstallDisplayNameMarkAllUsers=所有用户
UninstallDisplayNameMarkCurrentUser=当前用户

; *** 安装后错误
ErrorOpeningReadme=尝试打开自述文件时发生错误
ErrorRestartingComputer=安装程序无法重启电脑。请手动重启

; *** 卸载消息
UninstallNotFound=文件“%1”不存在，无法卸载
UninstallOpenError=无法打开文件“%1”，无法卸载
UninstallUnsupportedVer=此版本的卸载程序无法识别卸载日志文件“%1”的格式，无法卸载
UninstallUnknownEntry=卸载日志中存在未知条目 (%1)
ConfirmUninstall=您确定要彻底移除 %1 及其所有组件吗？
UninstallOnlyOnWin64=此安装只能在 64 位 Windows 上卸载
OnlyAdminCanUninstall=此安装只能由具有管理员权限的用户卸载
UninstallStatusLabel=请稍候，正在从您的电脑中移除 %1
UninstalledAll=%1 已成功从您的电脑中移除
UninstalledMost=%1 的卸载已完成。%n%n部分项目无法移除，需要手动删除
UninstalledAndNeedsRestart=要完成 %1 的卸载，必须重启您的电脑。%n%n您想现在重启吗？
UninstallDataCorrupted=文件“%1”已损坏，无法卸载

; *** 卸载共享文件提示
ConfirmDeleteSharedFileTitle=移除共享文件？
ConfirmDeleteSharedFile2=系统提示以下共享文件不再被任何程序使用。您希望卸载程序移除此共享文件吗？%n%n如果仍有程序在使用此文件而将其移除，这些程序可能无法正常运行。如果您不确定，请选择“否”。保留该文件不会对系统造成损害
SharedFileNameLabel=文件名:
SharedFileLocationLabel=位置:
WizardUninstalling=卸载状态
StatusUninstalling=正在卸载 %1...

; *** 关机阻止原因
ShutdownBlockReasonInstallingApp=正在安装 %1
ShutdownBlockReasonUninstallingApp=正在卸载 %1

; *** 自定义消息
[CustomMessages]

NameAndVersion=%1 版本 %2
AdditionalIcons=附加快捷方式:
CreateDesktopIcon=创建桌面快捷方式(&D)
CreateQuickLaunchIcon=创建快速启动栏快捷方式(&Q)
ProgramOnTheWeb=访问 %1 网站
UninstallProgram=卸载 %1
LaunchProgram=启动 %1
AssocFileExtension=将 %1 与 %2 文件扩展名关联(&A)
AssocingFileExtension=正在将 %1 与 %2 文件扩展名关联...
AutoStartProgramGroupDescription=开机启动:
AutoStartProgram=自动运行 %1
AddonHostProgramNotFound=在您选择的文件夹中未找到 %1。%n%n确定要继续吗？
