datalist_file="_includes/scheme-datalist.html"
template_path=~/.local/share/flavours/base16/templates/styles/templates/css-variables.mustache

# Add datalist opening tag
echo -n "<datalist id=\"scheme-list\">" > $datalist_file
# For each scheme
flavours list -l | while read slug; do
    # Get scheme file path
    scheme_path=$(flavours info $slug | head -1 | cut -d '@' -f2)
    # Build scheme
    flavours build $scheme_path $template_path > assets/schemes/$slug.css
    # Add entry to datalist
    echo -n "<option>$slug</option>" >> $datalist_file
done
# Add datalist closing tag
echo "</datalist>" >> $datalist_file
prettier $datalist_file > /tmp/scheme-datalist.html
mv /tmp/scheme-datalist.html $datalist_file
