<script lang="ts">
	import type { TocEntry } from '@/server/docs';

	let { toc, edit }: { toc: TocEntry[]; edit: string } = $props();

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

<nav aria-labelledby="toc-title" class="flex flex-col gap-3">
	{#if toc.length}
		<h2 id="toc-title" class="text-xs font-normal text-subtle">On this page</h2>
		<ul class="flex flex-col border-s border-border">
			{#each toc as entry (entry.id)}
				<li>
					<a
						href="#{entry.id}"
						aria-current={active === entry.id ? 'location' : undefined}
						class="-ms-px block border-s border-transparent py-1 text-sm leading-snug text-subtle transition-colors hover:text-strong aria-[current=location]:border-strong aria-[current=location]:text-strong {entry.depth === 3 ? 'ps-6' : 'ps-3'}"
					>
						{entry.text}
					</a>
				</li>
			{/each}
		</ul>
	{/if}
	<a href={edit} target="_blank" rel="noreferrer" class="mt-2 text-sm text-subtle hover:text-strong">Edit this page on GitHub</a>
</nav>
