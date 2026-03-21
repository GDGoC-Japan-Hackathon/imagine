import os

def replace_string_in_files(root_dir, search_text, replace_text, excludes=None):
    if excludes is None:
        excludes = [".git", ".dart_tool", "build", ".idea", ".metadata"]
    
    count = 0
    for root, dirs, files in os.walk(root_dir):
        # Exclude directories
        dirs[:] = [d for d in dirs if d not in excludes]
        
        for file in files:
            file_path = os.path.join(root, file)
            try:
                # Read file content as UTF-8
                with open(file_path, 'r', encoding='utf-8') as f:
                    content = f.read()
                
                if search_text in content:
                    print(f"Replacing at: {file_path}")
                    new_content = content.replace(search_text, replace_text)
                    with open(file_path, 'w', encoding='utf-8') as f:
                        f.write(new_content)
                    count += 1
            except (UnicodeDecodeError, PermissionError):
                # Skip binary files or access-restricted files
                continue
    return count

if __name__ == "__main__":
    project_root = r"c:\Users\sprin\Documents\works\imagine\frontend\imagine"
    old_name = "imagine"
    new_name = "imagine"
    
    # Use lowercase for package names and directory structures
    replaced_count = replace_string_in_files(project_root, old_name, new_name)
    print(f"Replacement complete. {replaced_count} files updated.")
