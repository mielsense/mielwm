<script lang="ts">
	import { CodeBlock } from '@mielui/svelte/components/code-block';
	import CopyPage from '@/components/CopyPage.svelte';
	import Icon from '@/components/Icon.svelte';
	import Sticker from '@/components/Sticker.svelte';
	import Toc from '@/components/Toc.svelte';
	import { groupLook, pageIcon } from '@/docs-look';
	import { ChevronLeftIcon, ChevronRightIcon } from '@/icons';
	import type { DocPage, Navigation } from '@/server/docs';
	import { docHref, site } from '@/site';

	let { doc, nav }: { doc: DocPage; nav: Navigation } = $props();

	// reading order: the groups, then the links above them
	const order = $derived([...nav.groups.flatMap((group) => group.pages), ...nav.top]);
	const at = $derived(order.findIndex((p) => p.slug === doc.slug));
	const prev = $derived(at > 0 ? order[at - 1] : undefined);
	const next = $derived(at >= 0 ? order[at + 1] : undefined);
	const groupOf = (slug: string) => nav.groups.find((g) => g.pages.some((p) => p.slug === slug));
	const group = $derived(groupOf(doc.slug));
	const edit = $derived(doc.slug === 'changelog' ? `${site.repo}/edit/main/CHANGELOG.md` : `${site.editBase}${doc.slug}.md`);
	const look = $derived(groupLook(group?.title));
</script>

<svelte:head>
	<title>{doc.slug === 'introduction' ? 'Docs' : doc.title} · mielwm docs</title>
	<meta name="description" content={doc.lead || site.description} />
	<meta property="og:title" content="{doc.title} · mielwm docs" />
	<meta property="og:description" content={doc.lead || site.description} />
</svelte:head>

{#snippet step(item: { slug: string; title: string }, label: 'Previous' | 'Next')}
	{@const target = groupLook(groupOf(item.slug)?.title)}
	<a
		href={docHref(item.slug)}
		class="tile group group/section press-soft flex items-center gap-3.5 p-4 hover:shadow-[var(--card-edge),0_6px_20px_-10px_rgb(0_0_0/0.2)] {label === 'Next' ? 'flex-row-reverse text-end' : ''}"
	>
		<Sticker icon={pageIcon(item.slug)} bg={target.mesh} size={32} />
		<span class="flex min-w-0 flex-1 flex-col gap-0.5">
			<span class="flex items-center gap-1 text-xs text-subtle {label === 'Next' ? 'justify-end' : ''}">
				{#if label === 'Previous'}<Icon icon={ChevronLeftIcon} size={12} />{/if}{label}{#if label === 'Next'}<Icon icon={ChevronRightIcon} size={12} />{/if}
			</span>
			<span class="truncate text-base text-strong">{item.title}</span>
		</span>
	</a>
{/snippet}

<!-- the article, with the outline as a slim rail at the window's right edge on wide screens -->
<div class="flex justify-center px-4 py-8 sm:px-8 sm:py-12 xl:px-10">
	<!-- the group's tint sits behind the title (.mesh-glow), its mesh frames the screenshots (.prose .frame) -->
	<article class="w-full max-w-[50rem] min-w-0" style:--mesh={look.mesh} style:--tint={look.tint}>
		<header class="group/section relative isolate mb-10 flex flex-col gap-3 pt-2">
			<div class="mesh-glow pointer-events-none absolute -inset-x-4 -top-8 -bottom-6 -z-10 sm:-inset-x-8" aria-hidden="true"></div>
			<div class="flex min-h-8 items-center gap-4">
				{#if group}
					<p class="flex items-center gap-2 text-sm font-medium text-strong">
						<Sticker icon={look.icon} bg={look.mesh} />
						{group.title}
					</p>
				{/if}
				<CopyPage source={doc.source} />
			</div>
			<h1 class="display text-4xl">{doc.title}</h1>
			{#if doc.lead}<p class="text-xl leading-normal text-default">{doc.lead}</p>{/if}
		</header>

		<!-- below xl the outline folds into the top of the page -->
		{#if doc.toc.length > 2}
			<details class="group mb-10 rounded-[12px] bg-plate shadow-[var(--card-edge)] xl:hidden">
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
			<a href={edit} target="_blank" rel="noreferrer" class="self-start text-sm text-subtle hover:text-strong">Edit this page on GitHub</a>
			<nav aria-label="Previous and next page" class="grid gap-4 sm:grid-cols-2">
				{#if prev}
					{@render step(prev, 'Previous')}
				{:else}
					<span class="hidden sm:block"></span>
				{/if}
				{#if next}{@render step(next, 'Next')}{/if}
			</nav>
		</footer>
	</article>

	<aside class="pointer-events-none fixed end-6 top-0 hidden h-dvh items-center xl:flex">
		<div class="pointer-events-auto"><Toc toc={doc.toc} /></div>
	</aside>
</div>
