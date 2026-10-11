<template><div v-html="content"></div></template>
<script>
node.innerHTML = content;
node.outerHTML = content;
node.insertAdjacentHTML('beforeend', content);
document.write(content);
const item = { dangerouslySetInnerHTML: { __html: content } };
</script>
