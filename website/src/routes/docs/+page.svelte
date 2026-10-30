<script lang="ts">
	import DocArticle from '@/components/DocArticle.svelte';

	let { data } = $props();
</script>

<DocArticle doc={data.doc} nav={data.nav} />
