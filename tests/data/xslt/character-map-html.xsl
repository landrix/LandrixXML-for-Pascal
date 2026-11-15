<?xml version="1.0" encoding="UTF-8"?>
<!-- Character maps with the html method: script content, the content type
     meta, URI attributes (an escaped URI is not mapped), a text with a
     mapped character is not indented, a boolean attribute with a mapped
     character is not minimized. -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:output method="html" use-character-maps="m"/>
  <xsl:character-map name="m">
    <xsl:output-character character="z" string="[Z]"/>
    <xsl:output-character character="t" string="[T]"/>
    <xsl:output-character character="b" string="[B]"/>
    <xsl:output-character character="&#xa0;" string="&amp;nbsp;"/>
  </xsl:character-map>
  <xsl:template match="/">
    <html>
      <head><script>z &lt; t</script></head>
      <body>
        <a href="z.html" title="z">z</a>
        <p>one
two</p>
        <p>z one
two</p>
        <p>a&#xa0;b</p>
        <input disabled="disabled"/>
        <input checked="checked"/>
      </body>
    </html>
  </xsl:template>
</xsl:stylesheet>
