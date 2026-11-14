<stylesheet version="2.0" xmlns="http://www.w3.org/1999/XSL/Transform">
<!-- element-available(): a name without a prefix is in the default
     namespace (here the XSLT one) -->
<output method="text"/>
<template match="/"><value-of separator="|" select="element-available('value-of'), element-available('foo'),
  function-available('concat')"/></template>
</stylesheet>
