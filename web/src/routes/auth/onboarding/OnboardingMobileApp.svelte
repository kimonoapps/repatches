<script lang="ts">
  import { Button } from '@immich/ui';
  import { mdiCellphoneArrowDownVariant } from '@mdi/js';
  import { t } from 'svelte-i18n';
</script>

<!-- Kimono: the phone app comes from Kimono, so this leaves for Kimono's own page (the server redirects /get-app). -->
<p>{$t('mobile_app_download_onboarding_note')}</p>

<Button
  size="medium"
  shape="semi-round"
  fullWidth
  href="/get-app"
  data-sveltekit-reload
  leadingIcon={mdiCellphoneArrowDownVariant}
>
  {$t('app_download_links')}
</Button>
