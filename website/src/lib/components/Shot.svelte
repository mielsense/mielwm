<script lang="ts">
	// A screenshot from static/shots in both themes, as AVIF with a WebP fallback. Each theme's copy
	// is hidden in the other one; lazy images that are hidden don't download. With `stage`, the shot
	// sits on that color mesh with film grain, the way miel.my sets its banners.
	let {
		name,
		widths,
		width,
		height,
		alt,
		sizes = '100vw',
		priority = false,
		stage,
		class: className = ''
	}: {
		name: string;
		widths: number[];
		width: number;
		height: number;
		alt: string;
		sizes?: string;
		priority?: boolean;
		stage?: string;
		class?: string;
	} = $props();

	const set = (theme: string, type: string) => widths.map((w) => `/shots/${name}-${theme}-${w}.${type} ${w}w`).join(', ');
</script>

{#snippet pictures()}
	{#each ['dark', 'light'] as theme (theme)}
		<picture class="only-{theme} block">
			<source type="image/avif" srcset={set(theme, 'avif')} {sizes} />
			<img
				src="/shots/{name}-{theme}-{widths[0]}.webp"
				srcset={set(theme, 'webp')}
				{sizes}
				{alt}
				{width}
				{height}
				loading="lazy"
				decoding="async"
				fetchpriority={priority ? 'high' : 'auto'}
				class="block h-auto w-full"
			/>
		</picture>
	{/each}
{/snippet}

{#if stage}
	<div class="grain rounded-[18px] p-3 sm:p-6 lg:p-8 {className}" style:background={stage}>
		<div class="overflow-hidden rounded-[11px] shadow-[0_0_0_1px_rgb(0_0_0/0.12),0_18px_40px_-12px_rgb(0_0_0/0.45)]">
			{@render pictures()}
		</div>
	</div>
{:else}
	{@render pictures()}
{/if}
