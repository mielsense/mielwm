import { browser } from '$app/environment';
import { ditherFrames } from '@/dither';

const KEY = 'theme';

/** Mirrors the `.dark` class on `<html>`, which the inline script in app.html sets before paint. */
class Theme {
	dark = $state(false);

	constructor() {
		if (!browser) return;
		const root = document.documentElement;
		const sync = () => (this.dark = root.classList.contains('dark'));
		sync();
		new MutationObserver(sync).observe(root, { attributes: true, attributeFilter: ['class'] });
	}

	/** Flips the theme. Given the point that was clicked, the new theme dithers in from it. */
	toggle(from?: { x: number; y: number }) {
		const root = document.documentElement;
		const dark = !this.dark;
		const apply = () => {
			root.classList.toggle('dark', dark);
			try {
				localStorage.setItem(KEY, dark ? 'dark' : 'light');
			} catch {
				// no storage, the choice just won't persist
			}
		};
		if (!from || !document.startViewTransition || matchMedia('(prefers-reduced-motion: reduce)').matches) return apply();

		// The new theme is masked by frames of an ordered dither spreading out from the click,
		// so it arrives in chunky pixels, like the dither shaders the old site was built on.
		const frames = ditherFrames(from, innerWidth, innerHeight);
		root.classList.add('theming');
		const transition = document.startViewTransition(apply);
		transition.ready.then(() =>
			root.animate(
				frames.map((mask) => ({ maskImage: mask, webkitMaskImage: mask })),
				{ duration: 700, easing: 'cubic-bezier(0.33, 1, 0.68, 1)', pseudoElement: '::view-transition-new(root)' }
			)
		);
		transition.finished.finally(() => root.classList.remove('theming'));
	}
}

export const theme = new Theme();
