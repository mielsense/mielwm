import adapter from '@sveltejs/adapter-vercel';
import { sveltekit } from '@sveltejs/kit/vite';
import tailwindcss from '@tailwindcss/vite';
import { fileURLToPath } from 'node:url';
import { defineConfig } from 'vite';

export default defineConfig({
	plugins: [
		tailwindcss(),
		sveltekit({
			compilerOptions: {
				runes: ({ filename }) =>
					filename.split(/[/\\]/).includes('node_modules') ? undefined : true
			},
			alias: { '@': 'src/lib' },
			adapter: adapter({ runtime: 'nodejs22.x' }),
			prerender: { handleMissingId: 'warn' }
		})
	],
	// the docs live one level up, in the repo's docs/ folder; the server reads image sizes from there
	define: { __DOCS_DIR__: JSON.stringify(fileURLToPath(new URL('../docs', import.meta.url))) },
	server: { fs: { allow: ['..'] } }
});
