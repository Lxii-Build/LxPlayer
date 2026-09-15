import os
import re

def analyze_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    max_depth = 0
    current_depth = 0
    max_pos = 0
    in_string = False
    string_char = None
    
    for i, char in enumerate(content):
        if in_string:
            if char == string_char and (i == 0 or content[i-1] != '\\'):
                in_string = False
        else:
            if char in '"\'' and (i == 0 or content[i-1] != '\\'):
                in_string = True
                string_char = char
            elif char in '({[':
                current_depth += 1
                if current_depth > max_depth:
                    max_depth = current_depth
                    max_pos = i
            elif char in ')}]':
                current_depth -= 1
    
    line_num = content[:max_pos].count('\n') + 1
    return max_depth, line_num

fp = r'd:\work\cyrene_music\lib\widgets\import_playlist_dialog.dart'
d, l = analyze_file(fp)
print(f'Max nesting depth: {d} at line {l}')
