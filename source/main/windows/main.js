import path from 'path';
import { app, BrowserWindow, ipcMain, Menu } from 'electron';
import { environment } from '../../common/environment';
import ipcApi from '../ipc';
import RendererErrorHandler from '../utils/rendererErrorHandler';

const rendererErrorHandler = new RendererErrorHandler();

const { isDev, isTest, buildLabel, isLinux } = environment;

export const createMainWindow = (isInSafeMode) => {
  let windowOptions = {};
  if (isTest) {
    windowOptions = {
      show: false,
      width: 1150,
      height: 870,
      webPreferences: {
        webviewTag: false,
      }
    };
  } else {
    windowOptions = {
      show: false,
      width: 1150,
      height: 870,
      webPreferences: {
        nodeIntegration: false,
        webviewTag: false,
        preload: path.join(`${__dirname}/../../source/main/utils/`, 'preload.js')
      }
    };
  }

  if (isLinux) {
    windowOptions.icon = path.join(process.env.DAEDALUS_INSTALL_DIRECTORY, 'icon.png');
  }

  // Construct new BrowserWindow
  const window = new BrowserWindow(windowOptions);

  rendererErrorHandler.setup(window, createMainWindow);

  window.setMinimumSize(900, 600);

  // Initialize our ipc api methods that can be called by the render processes
  ipcApi({ window });

  // Provide render process with an api to resize the main window
  ipcMain.on('resize-window', (event, { width, height, animate }) => {
    if (event.sender !== window.webContents) return;
    window.setSize(width, height, animate);
  });

  if (isDev) {
    window.webContents.openDevTools();
    // Focus the main window after dev tools opened
    window.webContents.on('devtools-opened', () => {
      window.focus();
      setImmediate(() => {
        window.focus();
      });
    });
  }

  window.loadURL(`file://${__dirname}/../renderer/index.html`);
  window.on('page-title-updated', event => { event.preventDefault(); });

  let title = buildLabel;
  if (isInSafeMode) title += ' [GPU safe mode]';
  window.setTitle(title);

  window.webContents.on('context-menu', (e, props) => {
    const contextMenuOptions = [
      { label: 'Copy', accelerator: 'CmdOrCtrl+C', role: 'copy' },
      { label: 'Paste', accelerator: 'CmdOrCtrl+V', role: 'paste' },
    ];

    if (isDev || isTest) {
      const { x, y } = props;
      contextMenuOptions.push({
        label: 'Inspect element',
        click() {
          window.inspectElement(x, y);
        }
      });
    }

    Menu.buildFromTemplate(contextMenuOptions).popup(window);
  });

  window.webContents.on('did-finish-load', () => {
    if (isTest) {
      window.showInactive(); // show without focusing the window
    } else {
      window.show(); // show also focuses the window
    }
  });

  window.on('closed', () => {
    app.quit();
  });

  window.webContents.on('did-fail-load', (err) => {
    rendererErrorHandler.onError('did-fail-load', err);
  });

  window.webContents.on('crashed', (err) => {
    rendererErrorHandler.onError('crashed', err);
  });

  return window;
};
