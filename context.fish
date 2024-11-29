#!/opt/homebrew/bin/fish

echo "" > temp.txt  # Clear/create temp file
for file in (fd . "paint/" -e odin)
    echo "// $file" >> temp.txt
    echo "" >> temp.txt
    cat $file >> temp.txt
    echo "" >> temp.txt
    echo "" >> temp.txt
end
cat temp.txt | pbcopy     # For macOS
# For Linux you'd use: cat temp.txt | xclip -selection clipboard
rm temp.txt
