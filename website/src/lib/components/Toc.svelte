<script lang="ts">
	import type { TocEntry } from '@/server/docs';

	let { toc }: { toc: TocEntry[] } = $props();

	// the current section is the last heading that has scrolled past the top fifth of the window
	let active = $state('');
	$effect(() => {
		const headings = toc.map((entry) => document.getElementById(entry.id)).filter((el) => el !== null);
		let frame = 0;
		const update = () => {
			frame = 0;
			const line = innerHeight * 0.2;
			let id = headings[0]?.id ?? '';
			for (const heading of headings) if (heading.getBoundingClientRect().top <= line) id = heading.id;
			// at the very bottom the last section wins, even when it is too short to reach the line
			if (innerHeight + scrollY >= document.documentElement.scrollHeight - 2) id = headings.at(-1)?.id ?? id;
			active = id;
		};
		const schedule = () => (frame ||= requestAnimationFrame(update));
		update();
		addEventListener('scroll', schedule, { passive: true });
		addEventListener('resize', schedule);
		return () => {
			removeEventListener('scroll', schedule);
			removeEventListener('resize', schedule);
			cancelAnimationFrame(frame);
		};
	});
</script>

<!-- a rail of dashes, one per heading, from ui.miel.my: the current one long and dark, the name of each beside it on hover or focus -->
{#if toc.length > 1}
	<nav aria-label="On this page" class="flex flex-col items-end">
		{#each toc as entry (entry.id)}
			<a
				href="#{entry.id}"
				aria-current={active === entry.id ? 'location' : undefined}
				class="toc-dash group relative flex h-3.5 w-14 items-center justify-end rounded-[4px] focus-visible:shadow-[var(--focus-ring)] focus-visible:outline-none"
			>
				<span
					class="block h-[1.5px] rounded-full bg-[color-mix(in_oklab,var(--color-strong)_30%,transparent)] transition-[width,background-color] duration-150 ease-out group-hover:w-12 group-hover:bg-strong group-focus-visible:bg-strong group-aria-[current=location]:bg-strong motion-reduce:transition-none
						{entry.depth === 3 ? 'w-3.5 group-aria-[current=location]:w-6' : 'w-6 group-aria-[current=location]:w-9'}"
				></span>
				<span
					class="pointer-events-none absolute end-[calc(100%+0.5rem)] rounded-[6px] bg-plate px-2 py-1 text-xs font-medium whitespace-nowrap text-strong opacity-0 shadow-[0_0_0_1px_var(--color-border),0_4px_12px_-4px_rgb(0_0_0/0.2)] transition-opacity duration-150 group-hover:opacity-100 group-focus-visible:opacity-100 motion-reduce:transition-none"
				>
					{entry.text}
				</span>
			</a>
		{/each}
	</nav>
{/if}
