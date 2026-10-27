<script lang="ts">
	import { Button } from '@mielui/svelte/components/button';
	import { page } from '$app/state';
</script>

<svelte:head><title>{page.status} · mielwm</title></svelte:head>

<div class="mx-auto flex w-full max-w-[36rem] flex-1 flex-col justify-center gap-4 px-4 py-16 sm:px-8">
	<p class="text-sm text-subtle tabular-nums">{page.status}</p>
	<h1 class="display text-4xl">{page.status === 404 ? 'Nothing lives here' : 'Something went wrong'}</h1>
	<p class="text-base text-subtle">{page.status === 404 ? 'The page moved or never existed. The docs or the home page should get you back on track.' : page.error?.message}</p>
	<div class="mt-2 flex gap-2">
		<Button href="/docs">Open the docs</Button>
		<Button href="/" variant="outline">Home</Button>
	</div>
</div>
