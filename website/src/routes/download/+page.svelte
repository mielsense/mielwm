<script lang="ts">
	import { Button } from '@mielui/svelte/components/button';
	import Icon from '@/components/Icon.svelte';
	import Sticker from '@/components/Sticker.svelte';
	import { ArrowUpRightIcon, BookIcon, ChevronRightIcon, DownloadIcon, ListIcon, type IconData } from '@/icons';
	import { mesh } from '@/mesh';
	import { site } from '@/site';

	let { data } = $props();

	const latest = $derived(data.latest);
	// the exact file when the release list loaded, the stable latest link when it didn't
	const dmg = $derived(latest?.dmg?.url ?? site.download);
	const file = $derived(latest ? `mielwm-${latest.version}.dmg` : 'mielwm.dmg');
	const day = (iso: string) => new Date(iso).toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric', timeZone: 'UTC' });
	const megabytes = (bytes: number) => `${(bytes / 1e6).toFixed(1)} MB`;
</script>

<svelte:head>
	<title>Download · mielwm</title>
	<meta name="description" content="Download mielwm{latest ? ` ${latest.version}` : ''} for macOS 15 or later on Apple silicon." />
	<meta property="og:title" content="Download · mielwm" />
</svelte:head>

{#snippet label(text: string, icon: IconData, bg: string)}
	<p class="flex items-center gap-2 text-sm font-medium text-strong">
		<Sticker {icon} {bg} />
		{text}
	</p>
{/snippet}

<main class="wrap flex flex-col gap-12 pt-12 pb-16 sm:gap-16 sm:pt-20 sm:pb-24">
	<!-- the release, and the one button that matters -->
	<section class="group/section stagger flex max-w-[46rem] flex-col gap-5" aria-labelledby="title">
		{@render label('Download', DownloadIcon, mesh.orange)}
		<h1 id="title" class="display text-5xl sm:text-6xl">{latest ? `mielwm ${latest.version}` : 'Download mielwm'}</h1>
		<p class="text-lg leading-relaxed text-subtle">
			{#if latest}Released {day(latest.date)}.{/if}
			Free and MIT licensed, for macOS 15 or later on a Mac with Apple silicon.
		</p>
		<div class="flex flex-wrap items-center gap-x-4 gap-y-3">
			<Button href={dmg} size="lg" class="ps-4">
				<Icon icon={DownloadIcon} size={16} />
				Download {file}
			</Button>
			{#if latest?.dmg}<span class="text-sm text-subtle tabular-nums">{megabytes(latest.dmg.size)}</span>{/if}
		</div>
	</section>

	<div class="grid grid-cols-[minmax(0,1fr)] gap-4 sm:gap-5 lg:grid-cols-12">
		<!-- install, in the order macOS asks -->
		<section class="tile group/section flex flex-col gap-5 p-6 sm:p-8 lg:col-span-7" aria-labelledby="install">
			{@render label('Install', BookIcon, mesh.violet)}
			<h2 id="install" class="display text-3xl">Open it the first time</h2>
			<ol class="flex flex-col gap-3.5 text-base leading-relaxed">
				<li class="flex items-start gap-3">
					<span class="key mt-0.5 shrink-0 text-xs">1</span>
					<span>Open <strong class="font-medium text-strong">{file}</strong> and drag mielwm into Applications.</span>
				</li>
				<li class="flex items-start gap-3">
					<span class="key mt-0.5 shrink-0 text-xs">2</span>
					<span>Open mielwm from Applications. mielwm is signed with its own certificate but not notarized by Apple, so macOS says it can't check the developer. Click Done.</span>
				</li>
				<li class="flex items-start gap-3">
					<span class="key mt-0.5 shrink-0 text-xs">3</span>
					<span>
						Go to System Settings &gt; Privacy &amp; Security, scroll down and click <strong class="font-medium text-strong">Open Anyway</strong>. Every release is signed
						with the same certificate, so macOS keeps your permissions when you update.
					</span>
				</li>
				<li class="flex items-start gap-3">
					<span class="key mt-0.5 shrink-0 text-xs">4</span>
					<span>Allow <strong class="font-medium text-strong">Accessibility</strong>, so mielwm can move and focus windows and hear its shortcuts.</span>
				</li>
				<li class="flex items-start gap-3">
					<span class="key mt-0.5 shrink-0 text-xs">5</span>
					<span>
						Allow <strong class="font-medium text-strong">Screen Recording</strong> for the live window pictures in the overview. Without it the overview shows
						plain cards. macOS applies it after mielwm restarts.
					</span>
				</li>
			</ol>
			<p class="text-sm text-subtle">
				<a class="link" href="/docs/install">Install</a> covers updating and uninstalling, and <a class="link" href="/docs/first-steps">First steps</a> the two
				permissions.
			</p>
		</section>

		<!-- the facts about the file -->
		<section class="tile flex flex-col gap-5 p-6 sm:p-8 lg:col-span-5" aria-labelledby="details">
			<h2 id="details" class="text-lg text-strong">Details</h2>
			<dl class="flex flex-col text-base">
				{#if latest}
					<div class="flex justify-between gap-6 border-t border-border py-3 first:border-t-0 first:pt-0">
						<dt class="text-subtle">Version</dt>
						<dd class="text-strong tabular-nums">{latest.version}</dd>
					</div>
					<div class="flex justify-between gap-6 border-t border-border py-3">
						<dt class="text-subtle">Released</dt>
						<dd class="text-strong">{day(latest.date)}</dd>
					</div>
				{/if}
				{#if latest?.dmg}
					<div class="flex justify-between gap-6 border-t border-border py-3">
						<dt class="text-subtle">Size</dt>
						<dd class="text-strong tabular-nums">{megabytes(latest.dmg.size)}</dd>
					</div>
				{/if}
				<div class="flex justify-between gap-6 border-t border-border py-3 first:border-t-0 first:pt-0">
					<dt class="text-subtle">Requires</dt>
					<dd class="text-end text-strong">macOS 15 or later, Apple silicon</dd>
				</div>
				{#if latest?.sha256}
					<div class="flex flex-col gap-2 border-t border-border pt-3">
						<dt class="text-subtle">SHA-256</dt>
						<dd class="flex flex-col gap-2">
							<code class="rounded-[8px] bg-selected px-2.5 py-2 font-mono text-[0.8rem] leading-relaxed break-all text-strong select-all">{latest.sha256}</code>
							<span class="text-sm text-subtle">
								Check it in Terminal with <code class="rounded-[6px] bg-selected px-1.5 py-0.5 font-mono text-[0.85em] text-strong">shasum -a 256 {file}</code>.
							</span>
						</dd>
					</div>
				{/if}
			</dl>
			<a href={site.releases} target="_blank" rel="noreferrer" class="group mt-auto inline-flex items-center gap-1 self-start text-sm text-strong">
				<span class="underline decoration-border-strong decoration-1 underline-offset-4 group-hover:decoration-current">Every release on GitHub</span>
				<Icon icon={ArrowUpRightIcon} size={12} />
			</a>
		</section>
	</div>

	<!-- what changed, straight from CHANGELOG.md -->
	{#if data.notes}
		<section class="group/section flex max-w-[50rem] flex-col gap-4" aria-labelledby="notes">
			{@render label('Release notes', ListIcon, mesh.sky)}
			<h2 id="notes" class="display text-3xl sm:text-4xl">What's in {data.notes.version}</h2>
			<div class="prose">{@html data.notes.html}</div>
			<a href="/docs/changelog" class="group inline-flex items-center gap-1 self-start text-sm text-strong">
				<span class="underline decoration-border-strong decoration-1 underline-offset-4 group-hover:decoration-current">The full changelog</span>
			</a>
		</section>
	{/if}

	{#if data.older.length}
		<section class="flex max-w-[50rem] flex-col gap-4" aria-labelledby="older">
			<h2 id="older" class="text-2xl text-strong">Older versions</h2>
			<div class="prose">
				<ul class="rows">
					{#each data.older as release (release.version)}
						<li>
							<a href={release.dmg?.url ?? release.page}>
								<span class="row-title tabular-nums">{release.version}</span>
								<span class="row-lead">
									{release.prerelease ? 'Pre-release, ' : ''}{day(release.date)}{release.dmg ? `, ${megabytes(release.dmg.size)}` : ''}
								</span>
								<Icon icon={ChevronRightIcon} size={14} class="row-chevron" />
							</a>
						</li>
					{/each}
				</ul>
			</div>
		</section>
	{/if}
</main>
