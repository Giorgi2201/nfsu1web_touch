import { mountKeyboardControls } from './keyboard';
import { markTouch, mountTouchSettings, noPinchZoom } from './touch';

/** Page navigation stays outside the game canvas and its input handlers. */
export function mountMenu() {
  markTouch();
  noPinchZoom();
  const buttons = [...document.querySelectorAll<HTMLButtonElement>('[data-screen]')];
  const screens = [...document.querySelectorAll<HTMLElement>('[data-menu-screen]')];
  const show = (name: string) => {
    for (const screen of screens) screen.hidden = screen.dataset.menuScreen !== name;
    for (const button of buttons) {
      const selected = button.dataset.screen === name;
      button.classList.toggle('selected', selected);
      if (selected) button.setAttribute('aria-current', 'page');
      else button.removeAttribute('aria-current');
    }
    document.body.dataset.screen = name;
  };
  buttons.forEach(button => button.addEventListener('click', () => show(button.dataset.screen!)));
  // Loading errors and the retry action must stay visible even from Options.
  new MutationObserver(() => {
    if (document.body.dataset.phase === 'error') show('play');
  }).observe(document.body, { attributes: true, attributeFilter: ['data-phase'] });
  const kbRoot = document.querySelector<HTMLElement>('#keyboard-controls');
  let touchRoot = document.querySelector<HTMLElement>('#touch-controls');
  if (!touchRoot && kbRoot?.parentElement) {
    touchRoot = document.createElement('div');
    touchRoot.id = 'touch-controls';
    kbRoot.parentElement.insertBefore(touchRoot, kbRoot);
  }
  mountTouchSettings(touchRoot);
  if (kbRoot) mountKeyboardControls(kbRoot);
  mountControllerSettings();
  show('play');
}

/** Keep controller options beside keyboard bindings, even though settings load later. */
function mountControllerSettings(): void {
  const source = document.querySelector<HTMLElement>('#settings-body');
  const target = document.querySelector<HTMLElement>('#controller-settings');
  if (!source || !target) return;
  const move = () => {
    for (const group of source.querySelectorAll<HTMLElement>(':scope > .group')) {
      if (group.querySelector('h3')?.textContent?.trim() === 'Controller') target.replaceChildren(group);
    }
  };
  new MutationObserver(move).observe(source, { childList: true, subtree: true });
  move();
}
