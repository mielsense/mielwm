<script lang="ts">
	import { CodeBlock } from '@mielui/svelte/components/code-block';
	import Icon from '@/components/Icon.svelte';
	import Toc from '@/components/Toc.svelte';
	import { ChevronLeftIcon, ChevronRightIcon } from '@/icons';
	import { site } from '@/site';

	let { data } = $props();

	const doc = $derived(data.doc);
	const order = $derived(data.groups.flatMap((group) => group.pages));
	const at = $derived(order.findIndex((p) => p.slug === doc.slug));
	const prev = $derived(at > 0 ? order[at - 1] : undefined);
	const next = $derived(at >= 0 ? order[at + 1] : undefined);
	const group = $derived(data.groups.find((g) => g.pages.some((p) => p.slug === doc.slug)));
	const edit = $derived(`${site.editBase}${doc.slug}.md`);
</script>

<svelte:head>
	<title>{doc.title} · mielwm docs</title>
	<meta name="description" content={doc.lead || site.description} />
	<meta property="og:title" content="{doc.title} · mielwm docs" />
	<meta property="og:description" content={doc.lead || site.description} />
</svelte:head>

<div class="flex justify-center gap-12 px-4 py-8 sm:px-8 sm:py-12 xl:px-12">
	<article class="w-full max-w-[44rem] min-w-0">
		<header class="mb-10 flex flex-col gap-3">
			{#if group}<p class="text-sm text-subtle">{group.title}</p>{/if}
			<h1 class="display text-4xl">{doc.title}</h1>
			{#if doc.lead}<p class="text-xl leading-normal text-subtle">{doc.lead}</p>{/if}
		</header>

		<!-- the table of contents folds into the top of the page below xl -->
		{#if doc.toc.length > 2}
			<details class="group mb-10 rounded-[12px] border border-border bg-plate xl:hidden">
				<summary class="flex h-11 cursor-pointer list-none items-center justify-between px-4 text-sm text-strong [&::-webkit-details-marker]:hidden">
					On this page
					<Icon icon={ChevronRightIcon} size={14} class="text-subtle transition-transform duration-200 group-open:rotate-90" />
				</summary>
				<ul class="flex flex-col gap-1 px-4 pb-4">
					{#each doc.toc as entry (entry.id)}
						<li class={entry.depth === 3 ? 'ps-4' : ''}><a href="#{entry.id}" class="text-sm text-subtle hover:text-strong">{entry.text}</a></li>
					{/each}
				</ul>
			</details>
		{/if}

		<div class="prose">
			{#each doc.segments as segment, i (i)}
				{#if segment.kind === 'html'}
					{@html segment.html}
				{:else}
					<CodeBlock code={segment.code} lang={segment.lang} copy="overlay" />
				{/if}
			{/each}
		</div>

		<footer class="mt-16 flex flex-col gap-6">
			<a href={edit} target="_blank" rel="noreferrer" class="self-start text-sm text-subtle hover:text-strong xl:hidden">Edit this page on GitHub</a>
			<nav aria-label="Previous and next page" class="grid gap-3 sm:grid-cols-2">
				{#if prev}
					<a href="/docs/{prev.slug}" class="group press-soft flex flex-col gap-1 rounded-[12px] border border-border bg-plate px-4 py-3.5 hover:border-border-strong">
						<span class="flex items-center gap-1 text-xs text-subtle"><Icon icon={ChevronLeftIcon} size={12} />Previous</span>
						<span class="text-base text-strong">{prev.title}</span>
					</a>
				{:else}
					<span class="hidden sm:block"></span>
				{/if}
				{#if next}
					<a href="/docs/{next.slug}" class="group press-soft flex flex-col items-end gap-1 rounded-[12px] border border-border bg-plate px-4 py-3.5 text-end hover:border-border-strong">
						<span class="flex items-center gap-1 text-xs text-subtle">Next<Icon icon={ChevronRightIcon} size={12} /></span>
						<span class="text-base text-strong">{next.title}</span>
					</a>
				{/if}
			</nav>
		</footer>
	</article>

	<aside class="hidden w-52 shrink-0 xl:block">
		<div class="sticky top-8 max-h-[calc(100dvh-4rem)] overflow-y-auto [scrollbar-width:none]">
			<Toc toc={doc.toc} {edit} />
		</div>
	</aside>
</div>
