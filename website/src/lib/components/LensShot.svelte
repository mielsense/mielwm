<script lang="ts">
	// A screenshot seen through mielwm's own lens: the same radial mapping as the overview's shader
	// (Sources/MielRender/Shaders.swift, lens_uv), strongest at the top of the page and flat once
	// the shot has scrolled up under the nav. Without WebGL, or with Reduce Motion, it is the plain shot.
	import type { ComponentProps } from 'svelte';
	import Shot from '@/components/Shot.svelte';
	import { theme } from '@/theme.svelte';

	let { strength = 0.22, magnify = 0.08, ...shot }: ComponentProps<typeof Shot> & { strength?: number; magnify?: number } = $props();

	let box = $state<HTMLDivElement>();
	let canvas = $state<HTMLCanvasElement>();
	let live = $state(false);

	const VERTEX = `attribute vec2 p; varying vec2 v; void main() { v = p; gl_Position = vec4(p, 0.0, 1.0); }`;
	// centered runs -1..1 on each axis, as in the app; past the picture's edge it fades to the page
	const FRAGMENT = `precision mediump float;
		varying vec2 v; uniform sampler2D t; uniform float k; uniform float zoom;
		void main() {
			vec2 uv = v * (1.0 + k * dot(v, v)) / zoom * 0.5 + 0.5;
			uv.y = 1.0 - uv.y;
			vec2 edge = min(uv, 1.0 - uv);
			float a = smoothstep(0.0, 0.003, min(edge.x, edge.y));
			gl_FragColor = vec4(texture2D(t, uv).rgb * a, a);
		}`;

	$effect(() => {
		void theme.dark; // the other theme's picture needs its own texture
		if (!box || !canvas || matchMedia('(prefers-reduced-motion: reduce)').matches) return;
		const gl = canvas.getContext('webgl', { premultipliedAlpha: true, antialias: false });
		const img = [...box.querySelectorAll('img')].find((i) => getComputedStyle(i.closest('picture') ?? i).display !== 'none');
		if (!gl || !img) return;

		const program = gl.createProgram()!;
		for (const [type, source] of [
			[gl.VERTEX_SHADER, VERTEX],
			[gl.FRAGMENT_SHADER, FRAGMENT]
		] as const) {
			const shader = gl.createShader(type)!;
			gl.shaderSource(shader, source);
			gl.compileShader(shader);
			gl.attachShader(program, shader);
		}
		gl.linkProgram(program);
		if (!gl.getProgramParameter(program, gl.LINK_STATUS)) return;
		gl.useProgram(program);
		gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer());
		gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]), gl.STATIC_DRAW);
		const at = gl.getAttribLocation(program, 'p');
		gl.enableVertexAttribArray(at);
		gl.vertexAttribPointer(at, 2, gl.FLOAT, false, 0, 0);
		const k = gl.getUniformLocation(program, 'k');
		const zoom = gl.getUniformLocation(program, 'zoom');
		const texture = gl.createTexture();
		gl.bindTexture(gl.TEXTURE_2D, texture);
		for (const wrap of [gl.TEXTURE_WRAP_S, gl.TEXTURE_WRAP_T]) gl.texParameteri(gl.TEXTURE_2D, wrap, gl.CLAMP_TO_EDGE);
		gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
		gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);

		let frame = 0;
		let ready = false;
		const draw = () => {
			frame = 0;
			if (!ready || !box || !canvas) return;
			const rect = box.getBoundingClientRect();
			const scale = Math.min(devicePixelRatio, 2);
			const width = Math.round(rect.width * scale), height = Math.round(rect.height * scale);
			if (canvas.width !== width || canvas.height !== height) Object.assign(canvas, { width, height });
			gl.viewport(0, 0, width, height);
			// 1 with the page at the top, 0 once the shot's top reaches 96px from the window's top
			const start = rect.top + scrollY - 96;
			const progress = Math.max(0, Math.min(1, 1 - scrollY / Math.max(1, start)));
			gl.uniform1f(k, strength * progress);
			gl.uniform1f(zoom, 1 + magnify * progress);
			gl.clearColor(0, 0, 0, 0);
			gl.clear(gl.COLOR_BUFFER_BIT);
			gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
		};
		const schedule = () => (frame ||= requestAnimationFrame(draw));
		const upload = () => {
			gl.bindTexture(gl.TEXTURE_2D, texture);
			gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, img);
			ready = live = true;
			schedule();
		};
		if (img.complete && img.naturalWidth) upload();
		else img.addEventListener('load', upload, { once: true });
		addEventListener('scroll', schedule, { passive: true });
		addEventListener('resize', schedule);
		return () => {
			img.removeEventListener('load', upload);
			removeEventListener('scroll', schedule);
			removeEventListener('resize', schedule);
			cancelAnimationFrame(frame);
			gl.deleteTexture(texture);
			gl.deleteProgram(program);
			live = false;
		};
	});
</script>

<div bind:this={box} class="relative">
	<!-- the real image stays in place for its size and its alt text; the canvas draws over it -->
	<div class="overflow-hidden rounded-[14px] shadow-[0_0_0_1px_rgb(0_0_0/0.14),0_30px_70px_-20px_rgb(0_0_0/0.45)] {live ? 'opacity-0' : ''}">
		<Shot {...shot} />
	</div>
	<canvas
		bind:this={canvas}
		aria-hidden="true"
		class="pointer-events-none absolute inset-0 size-full rounded-[14px] drop-shadow-[0_24px_40px_rgb(0_0_0/0.3)] {live ? '' : 'hidden'}"
	></canvas>
</div>
