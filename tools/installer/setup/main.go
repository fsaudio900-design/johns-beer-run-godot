// John's Beer Run — Windows installer / uninstaller with a graphical front end.
//
// The UI is a small HTML page (ui.html, embedded) shown in a chromeless Edge app
// window and served from 127.0.0.1 on a random port under a random token. If Edge
// is not available the installer falls back to plain message boxes.
//
// Installs per user (no admin prompt) to %LOCALAPPDATA%\Programs\JohnsBeerRun,
// adds Start menu / desktop shortcuts and an entry in Settings > Apps.
package main

import (
	"crypto/rand"
	_ "embed"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"
	"unsafe"
)

//go:embed JohnsBeerRun.exe
var gameExe []byte

//go:embed game.ico
var gameIcon []byte

//go:embed Licenses.txt
var licenses []byte

//go:embed ui.html
var uiPage []byte

// version is stamped at build time: go build -ldflags "-X main.version=2.9"
var version = "dev"

const (
	appName   = "John's Beer Run"
	appID     = "JohnsBeerRun"
	publisher = "Cessna"
	exeName   = "JohnsBeerRun.exe"
	uninstEx  = "Uninstall.exe"
	regKey    = `HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\` + appID
)

var (
	user32     = syscall.NewLazyDLL("user32.dll")
	messageBox = user32.NewProc("MessageBoxW")
	sysMetrics = user32.NewProc("GetSystemMetrics")
)

const (
	mbOK        = 0x0
	mbYesNo     = 0x4
	mbIconInfo  = 0x40
	mbIconQ     = 0x20
	mbIconErr   = 0x10
	mbTopmost   = 0x40000
	idYes       = 6
	createNoWin = 0x08000000
	detached    = 0x00000008
)

func msg(text, title string, flags uintptr) int {
	t, _ := syscall.UTF16PtrFromString(text)
	c, _ := syscall.UTF16PtrFromString(title)
	r, _, _ := messageBox.Call(0, uintptr(unsafe.Pointer(t)), uintptr(unsafe.Pointer(c)), flags|mbTopmost)
	return int(r)
}

func hidden(name string, args ...string) *exec.Cmd {
	c := exec.Command(name, args...)
	c.SysProcAttr = &syscall.SysProcAttr{HideWindow: true, CreationFlags: createNoWin}
	return c
}

/* ---------------------------------------------------------------- paths */

func installDir() string {
	base := os.Getenv("LOCALAPPDATA")
	if base == "" {
		base = filepath.Join(os.Getenv("USERPROFILE"), "AppData", "Local")
	}
	return filepath.Join(base, "Programs", appID)
}

func startMenuLnk() string {
	return filepath.Join(os.Getenv("APPDATA"), `Microsoft\Windows\Start Menu\Programs`, appName+".lnk")
}

var desktopOnce sync.Once
var desktopPath string

func desktopLnk() string {
	desktopOnce.Do(func() {
		out, err := hidden("powershell", "-NoProfile", "-NonInteractive", "-Command", "[Environment]::GetFolderPath('Desktop')").Output()
		if err == nil {
			desktopPath = strings.TrimSpace(string(out))
		}
		if desktopPath == "" {
			desktopPath = filepath.Join(os.Getenv("USERPROFILE"), "Desktop")
		}
	})
	return filepath.Join(desktopPath, appName+".lnk")
}

func exists(p string) bool { _, err := os.Stat(p); return err == nil }

func psQuote(s string) string { return "'" + strings.ReplaceAll(s, "'", "''") + "'" }

func makeShortcut(lnk, target, workdir string) error {
	icon := filepath.Join(workdir, "JohnsBeerRun.ico")
	if !exists(icon) {
		icon = target
	}
	script := fmt.Sprintf(`$s=(New-Object -ComObject WScript.Shell).CreateShortcut(%s);$s.TargetPath=%s;$s.WorkingDirectory=%s;$s.IconLocation=%s;$s.Description=%s;$s.Save()`,
		psQuote(lnk), psQuote(target), psQuote(workdir), psQuote(icon+",0"), psQuote(appName))
	return hidden("powershell", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", script).Run()
}

/* ---------------------------------------------------------------- registry */

func regAdd(name, typ, val string) error {
	return hidden("reg", "add", regKey, "/v", name, "/t", typ, "/d", val, "/f").Run()
}

func regGet(name string) string {
	out, err := hidden("reg", "query", regKey, "/v", name).Output()
	if err != nil {
		return ""
	}
	for _, line := range strings.Split(string(out), "\n") {
		f := strings.Fields(strings.TrimSpace(line))
		if len(f) >= 3 && strings.EqualFold(f[0], name) && strings.HasPrefix(f[1], "REG_") {
			i := strings.Index(line, f[1])
			return strings.TrimSpace(line[i+len(f[1]):])
		}
	}
	return ""
}

/* ---------------------------------------------------------------- state */

type installState struct {
	Mode             string `json:"mode"` // "install" or "uninstall"
	Installed        bool   `json:"installed"`
	InstalledVersion string `json:"installedVersion"`
	NewVersion       string `json:"newVersion"`
	Dir              string `json:"dir"`
	Cmp              int    `json:"cmp"` // installed vs this setup: -1 older, 0 same, 1 newer, 2 unknown
	Running          bool   `json:"running"`
	HasDesktop       bool   `json:"hasDesktop"`
	HasStartMenu     bool   `json:"hasStartMenu"`
}

func cmpVersions(a, b string) int {
	pa, pb := strings.Split(a, "."), strings.Split(b, ".")
	for i := 0; i < len(pa) || i < len(pb); i++ {
		var x, y int
		var err error
		if i < len(pa) {
			if x, err = strconv.Atoi(strings.TrimSpace(pa[i])); err != nil {
				return 2
			}
		}
		if i < len(pb) {
			if y, err = strconv.Atoi(strings.TrimSpace(pb[i])); err != nil {
				return 2
			}
		}
		if x < y {
			return -1
		}
		if x > y {
			return 1
		}
	}
	return 0
}

func gameRunning() bool {
	out, err := hidden("tasklist", "/FI", "IMAGENAME eq "+exeName, "/NH").Output()
	return err == nil && strings.Contains(strings.ToLower(string(out)), strings.ToLower(exeName))
}

func detect(mode string) installState {
	dir := installDir()
	if loc := regGet("InstallLocation"); loc != "" && exists(filepath.Join(loc, exeName)) {
		dir = loc
	}
	st := installState{Mode: mode, NewVersion: version, Dir: dir}
	st.Installed = exists(filepath.Join(dir, exeName))
	if st.Installed {
		st.InstalledVersion = regGet("DisplayVersion")
		if st.InstalledVersion == "" {
			st.InstalledVersion = "unknown"
			st.Cmp = 2
		} else {
			st.Cmp = cmpVersions(st.InstalledVersion, version)
		}
		st.Running = gameRunning()
	}
	st.HasDesktop = exists(desktopLnk())
	st.HasStartMenu = exists(startMenuLnk())
	return st
}

/* ---------------------------------------------------------------- work */

type progress struct {
	mu   sync.Mutex
	Pct  int
	Msg  string
	Done bool
	Err  string
	Busy bool
}

var prog progress

func setProg(pct int, m string) {
	prog.mu.Lock()
	prog.Pct, prog.Msg = pct, m
	prog.mu.Unlock()
	time.Sleep(150 * time.Millisecond) // lets the bar visibly move between quick steps
}

func finish(err error) {
	prog.mu.Lock()
	prog.Busy, prog.Done = false, true
	if err != nil {
		prog.Err = err.Error()
	} else {
		prog.Pct = 100
	}
	prog.mu.Unlock()
}

func stopGame() {
	hidden("taskkill", "/IM", exeName, "/F").Run()
	time.Sleep(500 * time.Millisecond)
}

func copySelf(dst string) error {
	self, err := os.Executable()
	if err != nil {
		return err
	}
	if abs, _ := filepath.Abs(dst); strings.EqualFold(abs, self) {
		return nil // running as the installed uninstaller already
	}
	in, err := os.Open(self)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.Create(dst)
	if err != nil {
		return err
	}
	defer out.Close()
	_, err = io.Copy(out, in)
	return err
}

type installOpts struct {
	Desktop   bool `json:"desktop"`
	StartMenu bool `json:"startMenu"`
}

func doInstall(o installOpts) error {
	dir := installDir()
	setProg(4, "Closing John's Beer Run if it's open…")
	stopGame()
	setProg(10, "Creating the install folder…")
	if err := os.MkdirAll(dir, 0755); err != nil {
		return fmt.Errorf("couldn't create %s: %v", dir, err)
	}
	setProg(14, "Copying the game…")
	game := filepath.Join(dir, exeName)
	tmp := game + ".new"
	f, err := os.Create(tmp)
	if err != nil {
		return fmt.Errorf("couldn't write the game files: %v", err)
	}
	const chunk = 1 << 20
	for off := 0; off < len(gameExe); off += chunk {
		end := off + chunk
		if end > len(gameExe) {
			end = len(gameExe)
		}
		if _, err := f.Write(gameExe[off:end]); err != nil {
			f.Close()
			os.Remove(tmp)
			return fmt.Errorf("couldn't write the game files: %v", err)
		}
		prog.mu.Lock()
		prog.Pct = 14 + 62*end/len(gameExe)
		prog.mu.Unlock()
		time.Sleep(15 * time.Millisecond)
	}
	f.Close()
	// swap in the new build (the old one may stay locked for a moment after taskkill)
	var swapErr error
	for i := 0; i < 10; i++ {
		os.Remove(game)
		if swapErr = os.Rename(tmp, game); swapErr == nil {
			break
		}
		time.Sleep(400 * time.Millisecond)
	}
	if swapErr != nil {
		os.Remove(tmp)
		return fmt.Errorf("the old version is still in use. Close the game and try again (%v)", swapErr)
	}
	setProg(80, "Writing licenses and the uninstaller…")
	os.WriteFile(filepath.Join(dir, "Licenses.txt"), licenses, 0644)
	os.WriteFile(filepath.Join(dir, "JohnsBeerRun.ico"), gameIcon, 0644)
	// the old web-version launcher left a page file behind; the Godot build doesn't need it
	os.Remove(filepath.Join(dir, "game.html.gz"))
	uninst := filepath.Join(dir, uninstEx)
	if err := copySelf(uninst); err != nil {
		return fmt.Errorf("couldn't write the uninstaller: %v", err)
	}
	setProg(86, "Creating shortcuts…")
	if o.StartMenu {
		makeShortcut(startMenuLnk(), game, dir)
	} else {
		os.Remove(startMenuLnk())
	}
	if o.Desktop {
		makeShortcut(desktopLnk(), game, dir)
	} else {
		os.Remove(desktopLnk())
	}
	setProg(94, "Registering with Windows…")
	regAdd("DisplayName", "REG_SZ", appName)
	regAdd("DisplayVersion", "REG_SZ", version)
	regAdd("Publisher", "REG_SZ", publisher)
	regAdd("DisplayIcon", "REG_SZ", filepath.Join(dir, "JohnsBeerRun.ico"))
	regAdd("InstallLocation", "REG_SZ", dir)
	regAdd("UninstallString", "REG_SZ", `"`+uninst+`" /uninstall`)
	regAdd("QuietUninstallString", "REG_SZ", `"`+uninst+`" /uninstall /quiet`)
	regAdd("NoModify", "REG_DWORD", "1")
	regAdd("NoRepair", "REG_DWORD", "1")
	regAdd("EstimatedSize", "REG_DWORD", fmt.Sprint((len(gameExe)*2)/1024))
	setProg(100, "Done.")
	return nil
}

// doUninstall removes everything. If we are the installed Uninstall.exe, the
// folder itself is removed by a short-lived cmd after we exit.
func doUninstall() (selfInDir bool, err error) {
	dir := detect("uninstall").Dir
	setProg(10, "Closing John's Beer Run if it's open…")
	stopGame()
	setProg(30, "Removing shortcuts…")
	os.Remove(startMenuLnk())
	os.Remove(desktopLnk())
	setProg(50, "Removing the Settings > Apps entry…")
	hidden("reg", "delete", regKey, "/f").Run()
	setProg(70, "Deleting game files…")
	os.Remove(filepath.Join(dir, exeName))
	os.Remove(filepath.Join(dir, "Licenses.txt"))
	os.RemoveAll(filepath.Join(os.TempDir(), "JohnsBeerRun-window"))
	self, _ := os.Executable()
	selfInDir = strings.EqualFold(filepath.Dir(self), dir)
	if !selfInDir {
		os.Remove(filepath.Join(dir, uninstEx))
		os.Remove(dir)
	}
	setProg(100, "Done.")
	return selfInDir, nil
}

var uninstallDir string

func scheduleFolderRemoval(dir string) {
	c := exec.Command("cmd", "/c", "ping 127.0.0.1 -n 4 >nul & rmdir /s /q \""+dir+"\"")
	c.SysProcAttr = &syscall.SysProcAttr{HideWindow: true, CreationFlags: createNoWin | detached}
	c.Start()
}

func launchGame() {
	dir := detect("install").Dir
	c := exec.Command(filepath.Join(dir, exeName))
	c.Dir = dir
	c.Start()
}

/* ---------------------------------------------------------------- GUI */

var (
	lastPing     atomic.Int64
	removeFolder atomic.Bool
	uiProc       *os.Process
)

func token() string {
	b := make([]byte, 16)
	rand.Read(b)
	return hex.EncodeToString(b)
}

func findEdge() string {
	for _, p := range []string{
		filepath.Join(os.Getenv("ProgramFiles(x86)"), `Microsoft\Edge\Application\msedge.exe`),
		filepath.Join(os.Getenv("ProgramFiles"), `Microsoft\Edge\Application\msedge.exe`),
		filepath.Join(os.Getenv("LocalAppData"), `Microsoft\Edge\Application\msedge.exe`),
	} {
		if exists(p) {
			return p
		}
	}
	return ""
}

func exitNow() {
	if removeFolder.Load() && uninstallDir != "" {
		scheduleFolderRemoval(uninstallDir)
	}
	if uiProc != nil {
		uiProc.Kill()
	}
	os.Exit(0)
}

func runGUI(mode string) bool {
	edge := findEdge()
	if edge == "" {
		return false
	}
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return false
	}
	tok := token()
	base := "/" + tok + "/"
	mux := http.NewServeMux()
	writeJSON := func(w http.ResponseWriter, v any) {
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Cache-Control", "no-store")
		json.NewEncoder(w).Encode(v)
	}
	post := func(h http.HandlerFunc) http.HandlerFunc {
		return func(w http.ResponseWriter, r *http.Request) {
			if r.Method != http.MethodPost {
				http.Error(w, "method", http.StatusMethodNotAllowed)
				return
			}
			h(w, r)
		}
	}
	mux.HandleFunc(base, func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != base {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		w.Header().Set("Cache-Control", "no-store")
		w.Write(uiPage)
	})
	mux.HandleFunc(base+"state", func(w http.ResponseWriter, r *http.Request) { writeJSON(w, detect(mode)) })
	mux.HandleFunc(base+"ping", func(w http.ResponseWriter, r *http.Request) {
		lastPing.Store(time.Now().Unix())
		w.WriteHeader(204)
	})
	mux.HandleFunc(base+"progress", func(w http.ResponseWriter, r *http.Request) {
		prog.mu.Lock()
		v := map[string]any{"pct": prog.Pct, "msg": prog.Msg, "done": prog.Done, "err": prog.Err, "busy": prog.Busy}
		prog.mu.Unlock()
		writeJSON(w, v)
	})
	startJob := func(w http.ResponseWriter, job func() error) {
		prog.mu.Lock()
		if prog.Busy {
			prog.mu.Unlock()
			http.Error(w, "busy", http.StatusConflict)
			return
		}
		prog.Busy, prog.Done, prog.Err, prog.Pct, prog.Msg = true, false, "", 0, "Starting…"
		prog.mu.Unlock()
		go func() { finish(job()) }()
		w.WriteHeader(202)
	}
	mux.HandleFunc(base+"install", post(func(w http.ResponseWriter, r *http.Request) {
		o := installOpts{Desktop: true, StartMenu: true}
		json.NewDecoder(io.LimitReader(r.Body, 4096)).Decode(&o)
		startJob(w, func() error { return doInstall(o) })
	}))
	mux.HandleFunc(base+"uninstall", post(func(w http.ResponseWriter, r *http.Request) {
		uninstallDir = detect("uninstall").Dir
		startJob(w, func() error {
			inDir, err := doUninstall()
			if inDir {
				removeFolder.Store(true)
			}
			return err
		})
	}))
	mux.HandleFunc(base+"launch", post(func(w http.ResponseWriter, r *http.Request) {
		launchGame()
		w.WriteHeader(204)
		go func() { time.Sleep(300 * time.Millisecond); exitNow() }()
	}))
	mux.HandleFunc(base+"quit", post(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(204)
		go func() { time.Sleep(300 * time.Millisecond); exitNow() }()
	}))
	go http.Serve(ln, mux)

	url := "http://" + ln.Addr().String() + base
	const W, H = 900, 600
	sw, _, _ := sysMetrics.Call(0)
	sh, _, _ := sysMetrics.Call(1)
	x, y := (int(sw)-W)/2, (int(sh)-H)/2
	if x < 0 {
		x = 0
	}
	if y < 0 {
		y = 0
	}
	profile := filepath.Join(os.TempDir(), "JohnsBeerRun-setup-window")
	cmd := exec.Command(edge, "--app="+url, fmt.Sprintf("--window-size=%d,%d", W, H), fmt.Sprintf("--window-position=%d,%d", x, y),
		"--no-first-run", "--no-default-browser-check", "--disable-features=Translate,msEdgeFirstRunExperience",
		"--user-data-dir="+profile)
	if cmd.Start() != nil {
		return false
	}
	uiProc = cmd.Process

	// stay alive while the window is open; never quit in the middle of a job
	start := time.Now()
	for {
		time.Sleep(time.Second)
		prog.mu.Lock()
		busy := prog.Busy
		prog.mu.Unlock()
		if busy {
			continue
		}
		lp := lastPing.Load()
		if lp == 0 {
			if time.Since(start) > 60*time.Second {
				// the window never showed up: fall back to message boxes
				if uiProc != nil {
					uiProc.Kill()
				}
				return false
			}
			continue
		}
		if time.Now().Unix()-lp > 6 {
			exitNow()
		}
	}
}

/* ---------------------------------------------------------------- fallback (no Edge) */

func installBoxes() {
	st := detect("install")
	q := appName + " " + version + " will be installed for your user account in:\n\n" + st.Dir + "\n\nInstall now?"
	if st.Installed {
		q = appName + " " + st.InstalledVersion + " is already installed in:\n\n" + st.Dir + "\n\nReplace it with version " + version + "?"
	}
	if msg(q, appName+" Setup", mbYesNo|mbIconQ) != idYes {
		return
	}
	if err := doInstall(installOpts{Desktop: true, StartMenu: true}); err != nil {
		msg("Setup couldn't finish:\n"+err.Error(), appName+" Setup", mbOK|mbIconErr)
		return
	}
	if msg(appName+" "+version+" is installed.\n\nPlay now?", appName+" Setup", mbYesNo|mbIconInfo) == idYes {
		launchGame()
	}
}

func uninstallBoxes(quiet bool) {
	if !quiet && msg("Remove "+appName+" from this computer?", appName+" Uninstall", mbYesNo|mbIconQ) != idYes {
		return
	}
	dir := detect("uninstall").Dir
	inDir, _ := doUninstall()
	if !quiet {
		msg(appName+" has been removed.", appName+" Uninstall", mbOK|mbIconInfo)
	}
	if inDir {
		scheduleFolderRemoval(dir)
	}
}

func main() {
	args := strings.ToLower(strings.Join(os.Args[1:], " "))
	if strings.Contains(args, "/uninstall") {
		if strings.Contains(args, "/quiet") {
			uninstallBoxes(true)
			return
		}
		if !runGUI("uninstall") {
			uninstallBoxes(false)
		}
		return
	}
	if strings.Contains(args, "/quiet") {
		doInstall(installOpts{Desktop: true, StartMenu: true})
		return
	}
	if !runGUI("install") {
		installBoxes()
	}
}
