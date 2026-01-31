const Applet = imports.ui.applet;
const Main = imports.ui.main;
const Mainloop = imports.mainloop;
const Settings = imports.ui.settings;
const PopupMenu = imports.ui.popupMenu;
const ModalDialog = imports.ui.modalDialog;
const Util = imports.misc.util;
const Gio = imports.gi.Gio;
const GLib = imports.gi.GLib;
const St = imports.gi.St;

class BatterySleepApplet extends Applet.TextApplet {
  constructor(metadata, orientation, panelHeight, instanceId) {
    super(orientation, panelHeight, instanceId);

    this._appletPath = metadata.path;

    this._timeoutId = null;
    this._lastActionTime = 0;

    this.settings = new Settings.AppletSettings(this, metadata.uuid, instanceId);
    this.settings.bindProperty(Settings.BindingDirection.BIDIRECTIONAL, "threshold", "threshold", this._onSettingsChanged, null);
    this.settings.bindProperty(Settings.BindingDirection.BIDIRECTIONAL, "action", "action", this._onSettingsChanged, null);
    this.settings.bindProperty(Settings.BindingDirection.BIDIRECTIONAL, "check_interval", "checkInterval", this._onSettingsChanged, null);
    this.settings.bindProperty(Settings.BindingDirection.BIDIRECTIONAL, "cooldown_minutes", "cooldownMinutes", this._onSettingsChanged, null);
    this.settings.bindProperty(Settings.BindingDirection.BIDIRECTIONAL, "notify", "notify", this._onSettingsChanged, null);
    this.settings.bindProperty(Settings.BindingDirection.BIDIRECTIONAL, "popup_alert", "popupAlert", this._onSettingsChanged, null);
    this.settings.bindProperty(Settings.BindingDirection.BIDIRECTIONAL, "popup_seconds", "popupSeconds", this._onSettingsChanged, null);
    this.settings.bindProperty(Settings.BindingDirection.BIDIRECTIONAL, "only_discharging", "onlyDischarging", this._onSettingsChanged, null);
    this.settings.bindProperty(Settings.BindingDirection.BIDIRECTIONAL, "force_critical", "forceCritical", this._onSettingsChanged, null);
    this.settings.bindProperty(Settings.BindingDirection.BIDIRECTIONAL, "critical_threshold", "criticalThreshold", this._onSettingsChanged, null);
    this.settings.bindProperty(Settings.BindingDirection.BIDIRECTIONAL, "critical_action", "criticalAction", this._onSettingsChanged, null);

    this._batteryPath = this._findBatteryPath();

    this._popupDialog = null;
    this._popupTimerId = null;
    this._lastClickTimeUs = 0;
    this._lastThreshold = Number(this.threshold || 15);
    this._lastCriticalThreshold = Number(this.criticalThreshold || 5);
    this._suppressNextAction = false;

    this.menuManager = new PopupMenu.PopupMenuManager(this);
    this.menu = new Applet.AppletPopupMenu(this, orientation);
    this.menuManager.addMenu(this.menu);
    this._buildMenu();
    this.menu.connect("open-state-changed", () => {
      this._updateMenuUi();
    });

    this.set_applet_tooltip("Battery Sleep Guard");
    this._updateLabel("...");
    this._reschedule();
  }

  _onSettingsChanged() {
    const currentThreshold = Number(this.threshold || 15);
    if (currentThreshold !== this._lastThreshold) {
      this._lastActionTime = 0;
      this._lastThreshold = currentThreshold;
      this._suppressNextAction = true;
    }
    const currentCriticalThreshold = Number(this.criticalThreshold || 5);
    if (currentCriticalThreshold !== this._lastCriticalThreshold) {
      this._lastActionTime = 0;
      this._lastCriticalThreshold = currentCriticalThreshold;
      this._suppressNextAction = true;
    }
    this._updateMenuUi();
    this._reschedule();
  }

  _buildMenu() {
    this._thresholdLabelItem = new PopupMenu.PopupMenuItem("Threshold: --%", { reactive: false });
    this.menu.addMenuItem(this._thresholdLabelItem);

    this._thresholdSlider = new PopupMenu.PopupSliderMenuItem(this._thresholdToSlider(this.threshold || 15));
    this._thresholdSlider.connect("value-changed", (item, value) => {
      const newThreshold = this._sliderToThreshold(value);
      if (newThreshold !== this.threshold) {
        this.settings.setValue("threshold", newThreshold);
      }
      if (newThreshold !== this._lastThreshold) {
        this._lastActionTime = 0;
        this._lastThreshold = newThreshold;
        this._suppressNextAction = true;
      }
      if (this._thresholdLabelItem) {
        this._thresholdLabelItem.label.text = `Threshold: ${newThreshold}%`;
      }
    });
    this.menu.addMenuItem(this._thresholdSlider);

    this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());

    this._actionHeaderItem = new PopupMenu.PopupMenuItem("Action", { reactive: false });
    this.menu.addMenuItem(this._actionHeaderItem);

    this._actionSuspendItem = new PopupMenu.PopupMenuItem("Suspend");
    this._actionSuspendItem.connect("activate", () => {
      this.settings.setValue("action", "suspend");
      this._updateMenuUi();
    });
    this.menu.addMenuItem(this._actionSuspendItem);

    this._actionHibernateItem = new PopupMenu.PopupMenuItem("Hibernate");
    this._actionHibernateItem.connect("activate", () => {
      this.settings.setValue("action", "hibernate");
      this._updateMenuUi();
    });
    this.menu.addMenuItem(this._actionHibernateItem);

    this._actionAlertItem = new PopupMenu.PopupMenuItem("Alert only");
    this._actionAlertItem.connect("activate", () => {
      this.settings.setValue("action", "alert");
      this._updateMenuUi();
    });
    this.menu.addMenuItem(this._actionAlertItem);

    this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());

    this._statusItem = new PopupMenu.PopupMenuItem("Status: --", { reactive: false });
    this.menu.addMenuItem(this._statusItem);

    this._cooldownItem = new PopupMenu.PopupMenuItem("Cooldown: --", { reactive: false });
    this.menu.addMenuItem(this._cooldownItem);

    this._updateMenuUi();
  }

  _updateMenuUi() {
    if (this._thresholdLabelItem) {
      const t = Math.round(Number(this.threshold || 15));
      this._thresholdLabelItem.label.text = `Threshold: ${t}%`;
    }

    if (this._thresholdSlider) {
      const sliderValue = this._thresholdToSlider(this.threshold || 15);
      this._thresholdSlider.setValue(sliderValue);
    }

    if (this._actionSuspendItem && this._actionHibernateItem && this._actionAlertItem) {
      const action = this._normalizedAction();
      this._setRadioOrnament(this._actionSuspendItem, action === "suspend");
      this._setRadioOrnament(this._actionHibernateItem, action === "hibernate");
      this._setRadioOrnament(this._actionAlertItem, action === "alert");
    }

    if (this._cooldownItem) {
      this._cooldownItem.label.text = this._cooldownLabel();
    }
  }

  _thresholdToSlider(value) {
    const clamped = Math.max(1, Math.min(50, Number(value || 15)));
    return clamped / 50;
  }

  _setRadioOrnament(item, selected) {
    if (!item) return;
    if (typeof item.setOrnament !== "function") return;
    if (item.setOrnament.length >= 2) {
      item.setOrnament(PopupMenu.OrnamentType.DOT, selected);
    } else {
      item.setOrnament(selected ? PopupMenu.OrnamentType.DOT : PopupMenu.OrnamentType.NONE);
    }
  }

  _sliderToThreshold(value) {
    const percent = Math.round(value * 50);
    return Math.max(1, Math.min(50, percent));
  }

  _reschedule() {
    if (this._timeoutId) {
      Mainloop.source_remove(this._timeoutId);
      this._timeoutId = null;
    }

    const interval = Math.max(5, Number(this.checkInterval || 30));
    this._timeoutId = Mainloop.timeout_add_seconds(interval, () => {
      this._checkBattery();
      return true;
    });

    this._checkBattery();
  }

  _findBatteryPath() {
    try {
      const dir = Gio.File.new_for_path("/sys/class/power_supply");
      const enumerator = dir.enumerate_children("standard::name", Gio.FileQueryInfoFlags.NONE, null);
      let info;
      while ((info = enumerator.next_file(null)) !== null) {
        const name = info.get_name();
        if (name.startsWith("BAT")) {
          return `/sys/class/power_supply/${name}`;
        }
      }
    } catch (e) {
      // ignore
    }
    return null;
  }

  _readFile(path) {
    try {
      const [ok, contents] = GLib.file_get_contents(path);
      if (!ok) return null;
      return contents.toString().trim();
    } catch (e) {
      return null;
    }
  }

  _getBatteryStatus() {
    if (!this._batteryPath) return null;
    const capacityStr = this._readFile(`${this._batteryPath}/capacity`);
    const statusStr = this._readFile(`${this._batteryPath}/status`);
    if (capacityStr === null || statusStr === null) return null;

    const percent = parseInt(capacityStr, 10);
    if (Number.isNaN(percent)) return null;

    return { percent, status: statusStr };
  }

  _shortStatus(status) {
    if (!status) return "";
    if (status === "Discharging") return "↓";
    if (status === "Charging") return "↑";
    if (status === "Full") return "✓";
    return status;
  }

  _updateLabel(text) {
    this.set_applet_label(text);
  }

  _modeFlags() {
    const action = this._normalizedAction();
    const actionFlag = action === "alert" ? "A" : (action === "hibernate" ? "H" : "S");
    const alertFlag = (this.popupAlert && action !== "alert") ? "+P" : "";
    const flags = `${actionFlag}${alertFlag}`;
    return flags.length ? flags : "S";
  }

  _normalizedAction() {
    const raw = (this.action || "suspend").toString();
    const lowered = raw.toLowerCase();
    if (lowered === "alert" || lowered === "alert only") return "alert";
    if (lowered === "hibernate") return "hibernate";
    return "suspend";
  }

  _normalizedCriticalAction() {
    const raw = (this.criticalAction || "suspend").toString();
    const lowered = raw.toLowerCase();
    return lowered === "hibernate" ? "hibernate" : "suspend";
  }

  _cooldownRemainingMs() {
    const cooldownMs = Math.max(1, Number(this.cooldownMinutes || 10)) * 60 * 1000;
    if (!this._lastActionTime) return 0;
    const remaining = cooldownMs - (Date.now() - this._lastActionTime);
    return Math.max(0, remaining);
  }

  _cooldownLabel() {
    const remaining = this._cooldownRemainingMs();
    if (remaining <= 0) return "Cooldown: ready";
    const totalSeconds = Math.ceil(remaining / 1000);
    const minutes = Math.floor(totalSeconds / 60);
    const seconds = totalSeconds % 60;
    if (minutes > 0) return `Cooldown: ${minutes}m ${seconds}s`;
    return `Cooldown: ${seconds}s`;
  }

  _runDeepSleepFix() {
    const scriptPath = `${this._appletPath}/fix-mint-sleep-wake-deep.sh`;
    Util.spawnCommandLine(`pkexec bash "${scriptPath}"`);
  }

  on_fix_deep_sleep() {
    this._runDeepSleepFix();
  }

  _shouldTriggerAction(percent, status) {
    const threshold = Number(this.threshold || 15);
    if (percent > threshold) return false;
    if (this.onlyDischarging && status !== "Discharging") return false;

    const cooldownMs = Math.max(1, Number(this.cooldownMinutes || 10)) * 60 * 1000;
    const now = Date.now();
    if (now - this._lastActionTime < cooldownMs) return false;

    return true;
  }

  _shouldForceCriticalAction(percent, status) {
    if (!this.forceCritical) return false;
    if (this._normalizedAction() !== "alert") return false;
    const criticalThreshold = Number(this.criticalThreshold || 5);
    if (percent > criticalThreshold) return false;
    if (this.onlyDischarging && status !== "Discharging") return false;
    if (this._cooldownRemainingMs() > 0) return false;
    return true;
  }

  _performAction(percent, overrideAction) {
    const action = overrideAction || this._normalizedAction();
    if (action === "alert") {
      this._lastActionTime = Date.now();
      return;
    }
    const cmd = action === "hibernate" ? "systemctl hibernate" : "systemctl suspend";

    if (this.notify) {
      Main.notify("Battery Sleep Guard", `Battery at ${percent}%. ${action === "hibernate" ? "Hibernating" : "Suspending"} now.`);
    }

    this._lastActionTime = Date.now();
    Util.spawnCommandLine(cmd);
  }

  _showPopupAlert(percent) {
    if (this._popupDialog) {
      return;
    }

    const action = this._normalizedAction();
    const actionLabel = action === "hibernate" ? "Hibernate" : (action === "alert" ? "Alert" : "Suspend");
    const countdownTotal = Math.max(5, Number(this.popupSeconds || 20));
    let remaining = countdownTotal;

    this._popupDialog = new ModalDialog.ModalDialog();
    const content = new St.BoxLayout({ vertical: true, style_class: "battery-sleep-popup" });
    const title = new St.Label({
      text: "Low battery",
      style_class: "battery-sleep-popup-title"
    });
    const body = new St.Label({
      text: action === "alert"
        ? `Battery at ${percent}%. Alert will close in ${remaining}s.`
        : `Battery at ${percent}%. ${actionLabel} in ${remaining}s.`,
      style_class: "battery-sleep-popup-body"
    });

    content.add(title);
    content.add(body);
    this._popupDialog.contentLayout.add(content);

    if (action === "alert") {
      this._popupDialog.setButtons([
        {
          label: "Dismiss",
          action: () => {
            this._closePopup(true);
          },
          key: "Escape",
          default: true
        }
      ]);
    } else {
      this._popupDialog.setButtons([
        {
          label: "Cancel",
          action: () => {
            this._closePopup(true);
          },
          key: "Escape"
        },
        {
          label: actionLabel + " now",
          action: () => {
            this._closePopup(false);
            this._performAction(percent);
          },
          default: true
        }
      ]);
    }

    this._popupDialog.open();

    this._popupTimerId = Mainloop.timeout_add_seconds(1, () => {
      remaining -= 1;
      if (!this._popupDialog) return false;
      if (remaining <= 0) {
        if (action === "alert") {
          this._closePopup(true);
        } else {
          this._closePopup(false);
          this._performAction(percent);
        }
        return false;
      }
      body.set_text(action === "alert"
        ? `Battery at ${percent}%. Alert will close in ${remaining}s.`
        : `Battery at ${percent}%. ${actionLabel} in ${remaining}s.`);
      return true;
    });
  }

  _closePopup(setCooldown) {
    if (this._popupTimerId) {
      Mainloop.source_remove(this._popupTimerId);
      this._popupTimerId = null;
    }
    if (this._popupDialog) {
      this._popupDialog.close();
      this._popupDialog.destroy();
      this._popupDialog = null;
    }
    if (setCooldown) {
      this._lastActionTime = Date.now();
    }
  }

  _checkBattery() {
    const info = this._getBatteryStatus();
    if (!info) {
      this._updateLabel(`N/A ${this._modeFlags()}`.trim());
      if (this._statusItem) this._statusItem.label.text = "Status: N/A";
      return;
    }

    const statusIcon = this._shortStatus(info.status);
    this._updateLabel(`${info.percent}%${statusIcon} ${this._modeFlags()}`.trim());
    if (this._statusItem) this._statusItem.label.text = `Status: ${info.percent}% ${info.status}`;
    if (this._cooldownItem) this._cooldownItem.label.text = this._cooldownLabel();

    if (this._suppressNextAction) {
      this._suppressNextAction = false;
      return;
    }

    if (this._shouldForceCriticalAction(info.percent, info.status)) {
      this._performAction(info.percent, this._normalizedCriticalAction());
      return;
    }

    if (this._shouldTriggerAction(info.percent, info.status)) {
      const action = this._normalizedAction();
      if (action === "alert") {
        this._showPopupAlert(info.percent);
      } else if (this.popupAlert) {
        this._showPopupAlert(info.percent);
      } else {
        this._performAction(info.percent);
      }
    }
  }

  on_applet_removed_from_panel() {
    if (this._timeoutId) {
      Mainloop.source_remove(this._timeoutId);
      this._timeoutId = null;
    }
    this._closePopup(false);
    if (this.settings) {
      this.settings.finalize();
    }
  }

  on_applet_clicked() {
    const nowUs = GLib.get_monotonic_time();
    const doubleClickThresholdUs = 350 * 1000;
    if (nowUs - this._lastClickTimeUs <= doubleClickThresholdUs) {
      this._lastClickTimeUs = 0;
      this.configureApplet();
      return;
    }
    this._lastClickTimeUs = nowUs;
    if (this.menu) {
      this.menu.toggle();
    }
  }

  on_applet_middle_clicked() {
    if (this.menu) {
      this.menu.toggle();
    }
  }

  on_applet_right_clicked() {
    if (this.menu) {
      this._updateMenuUi();
      this.menu.toggle();
    }
  }
}

function main(metadata, orientation, panelHeight, instanceId) {
  return new BatterySleepApplet(metadata, orientation, panelHeight, instanceId);
}
