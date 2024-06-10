#!/bin/bash

echo "Please enter the path to the folder:"
read input_folder

log_file="script_log.txt"
echo "Script started at $(date)" > $log_file

report_file="report.html"
echo "<html><head><title>Project Report</title></head><body>" > $report_file
echo "<h1>Project Report for $input_folder</h1>" >> $report_file
echo "<table border='1'><tr><th>Subfolder</th><th>Git Repository</th><th>Pull Status</th><th>Project Types</th><th>Build Status</th><th>Execution Status</th></tr>" >> $report_file

git_repos=()
messages=()

check_git_repo() {
  local folder=$1
  echo "Checking Git repositories in $folder" >> $log_file
  echo "Checking for Git repositories..."
  for subfolder in "$folder"/*/; do
    subfolder_name=$(basename "$subfolder")
    if [ -d "$subfolder/.git" ]; then
      messages+=("$subfolder_name is a Git repository")
      git_repos+=("$subfolder")
      echo "$subfolder_name is a Git repository"
    else
      messages+=("$subfolder_name is not a Git repository")
      echo "$subfolder_name is not a Git repository"
    fi
  done
  echo "Finished checking for Git repositories."
}

pull_latest_version() {
  local folder=$1
  echo "Pulling latest version in $folder" >> $log_file
  echo "Pulling latest version for $(basename "$folder")..."
  git -C "$folder" pull >> $log_file 2>&1
  if [ $? -eq 0 ]; then
    echo "Pull Success"
    return 0
  else
    echo "Pull Failed"
    return 1
  fi
}

determine_project_types() {
  local folder_name=$1
  local project_types=()

  if git -C "$folder_name" ls-files | grep -q '\.cpp'; then
    project_types+=("C++")
  fi

  if git -C "$folder_name" ls-files | grep -q '\.java'; then
    project_types+=("Java")
  fi

  if git -C "$folder_name" ls-files | grep -q '\.py'; then
    project_types+=("Python")
  fi

  if [ ${#project_types[@]} -eq 0 ]; then
    echo "Unknown"
  else
    echo "${project_types[@]}"
  fi
}

build_cpp_project() {
  local folder=$1
  echo "Building C++ project in $folder" >> $log_file
  echo "Building C++ project in $(basename "$folder")..."
  if ls "$folder"/*.cpp > /dev/null 2>&1; then
    g++ -o "$folder/project_executable" "$folder"/*.cpp >> $log_file 2>&1
    if [ $? -eq 0 ]; then
      echo "Build Success"
      return 0
    else
      echo "Build Failed"
      return 1
    fi
  else
    echo "No C++ source files found."
    return 1
  fi
}

build_java_project() {
  local folder=$1
  echo "Building Java project in $folder" >> $log_file
  echo "Building Java project in $(basename "$folder")..."
  if ls "$folder"/*.java > /dev/null 2>&1; then
    javac -d "$folder" "$folder"/*.java >> $log_file 2>&1
    if [ $? -eq 0 ]; then
      main_class=$(grep -l 'public static void main' "$folder"/*.java | sed 's/.*\/\(.*\)\.java/\1/')
      jar cfe "$folder/project_executable.jar" "$main_class" -C "$folder" . >> $log_file 2>&1
      if [ $? -eq 0 ]; then
        echo "Build Success"
        return 0
      else
        echo "Build Failed"
        return 1
      fi
    else
      echo "Compilation Failed"
      return 1
    fi
  else
    echo "No Java source files found."
    return 1
  fi
}

build_python_project() {
  local folder=$1
  echo "Building Python project in $folder" >> $log_file
  echo "Building Python project in $(basename "$folder")..."
  if ls "$folder"/*.py > /dev/null 2>&1; then
    if ! python3 -m venv "$folder/venv"; then
      echo "Failed to create virtual environment. Ensure 'python3-venv' is installed."
      return 1
    fi
    source "$folder/venv/bin/activate"
    pip install pyinstaller >> $log_file 2>&1
    for py_file in "$folder"/*.py; do
      pyinstaller --onefile "$py_file" --distpath "$folder" >> $log_file 2>&1
    done
    deactivate
    if [ $? -eq 0 ]; then
      echo "Build Success"
      return 0
    else
      echo "Build Failed"
      return 1
    fi
  else
    echo "No Python source files found."
    return 1
  fi
}

execute_executable() {
  local folder=$1
  local project_type=$2

  echo "Executing $(basename "$folder") project..."
  case $project_type in
    "C++")
      "$folder/project_executable" >> $log_file 2>&1
      ;;
    "Java")
      java -jar "$folder/project_executable.jar" >> $log_file 2>&1
      ;;
    "Python")
      for exe in "$folder"/dist/*; do
        if [[ -x "$exe" ]]; then
          "$exe" >> $log_file 2>&1
          if [ $? -ne 0 ]; then
            echo "Execution of $exe failed" >> $log_file
            return 1
          fi
        fi
      done
      ;;
    *)
      echo "Unknown project type. Skipping execution." >> $log_file
      ;;
  esac

  if [ $? -eq 0 ]; then
    echo "Execution Success"
    return 0
  else
    echo "Execution Failed"
    return 1
  fi
}

check_git_repo "$input_folder"

for subfolder in "${git_repos[@]}"; do
  subfolder_name=$(basename "$subfolder")

  pull_latest_version "$subfolder"
  pull_status_text="Pull Success"
  if [ $? -ne 0 ]; then
    pull_status_text="Pull Failed"
  fi

  project_types=$(determine_project_types "$subfolder")

  echo "Processing $subfolder_name..." >> $log_file

  IFS=' ' read -r -a types_array <<< "$project_types"
  build_status_text="Build Success"
  execution_status_text="Execution Success"
  for project_type in "${types_array[@]}"; do
    case $project_type in
      "C++")
        build_cpp_project "$subfolder"
        if [ $? -ne 0 ]; then
          build_status_text="Build Failed"
        fi
        ;;
      "Java")
        build_java_project "$subfolder"
        if [ $? -ne 0 ]; then
          build_status_text="Build Failed"
        fi
        ;;
      "Python")
        build_python_project "$subfolder"
        if [ $? -ne 0 ]; then
          build_status_text="Build Failed"
        fi
        ;;
      *)
        build_status_text="Unknown project type. Skipping build."
        ;;
    esac

    if [ "$build_status_text" == "Build Success" ]; then
      execute_executable "$subfolder" "$project_type"
      if [ $? -ne 0 ]; then
        execution_status_text="Execution Failed"
      fi
    else
      execution_status_text="Not Applicable"
    fi
  done

  echo "<tr><td>$subfolder_name</td><td>Yes</td><td>$pull_status_text</td><td>$project_types</td><td>$build_status_text</td><td>$execution_status_text</td></tr>" >> $report_file
done

echo "</table></body></html>" >> $report_file

for message in "${messages[@]}"; do
  echo "$message"
done

echo "Report generated: $report_file"
echo "Log file generated: $log_file"
