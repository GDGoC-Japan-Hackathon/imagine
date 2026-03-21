import os

def replace_in_files(root_dir, target, replacement, excludes=None):
    if excludes is None:
        excludes = []
    
    for root, dirs, files in os.walk(root_dir):
        # Exclude directories
        dirs[:] = [d for d in dirs if d not in excludes]
        
        for file in files:
            file_path = os.path.join(root, file)
            try:
                # First read as UTF-8
                with open(file_path, 'r', encoding='utf-8') as f:
                    content = f.read()
                
                if target in content:
                    print(f"Updating {file_path}")
                    new_content = content.replace(target, replacement)
                    with open(file_path, 'w', encoding='utf-8') as f:
                        f.write(new_content)
            except (UnicodeDecodeError, PermissionError):
                # Skip binary files or permission denied files
                continue

if __name__ == "__main__":
    project_root = r"c:\Users\sprin\Documents\works\imagine\frontend\imagine"
    target_str = "imagine"
    replacement_str = "imagine"
    exclude_dirs = [".git", ".dart_tool", "build", ".idea", ".metadata"]
    
    replace_in_files(project_root, target_str, replacement_str, exclude_dirs)
    print("Replacement complete.")
