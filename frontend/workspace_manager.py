import os
from pathlib import Path

# تحديد المكان الرئيسي للـ Workspace على الجهاز
HOME_DIR = Path.home()
WORKSPACE_DIR = HOME_DIR / "AegisWorkspace"

def init_workspace():
    """تكريت الفولدرات الأساسية للـ Workspace"""
    subfolders = [
        WORKSPACE_DIR / "courses",
        WORKSPACE_DIR / "projects",
        WORKSPACE_DIR / "templates",
        WORKSPACE_DIR / "config"
    ]
    
    for folder in subfolders:
        folder.mkdir(parents=True, exist_ok=True)
        print(f"[OK] Created/Verified: {folder}")

def create_course_dir(course_code):
    """تكريت فولدر لمادة معينة وإنشاء ملف مبدئي جواه"""
    course_path = WORKSPACE_DIR / "courses" / course_code
    course_path.mkdir(parents=True, exist_ok=True)
    
    (course_path / "assignments").mkdir(exist_ok=True)
    (course_path / "labs").mkdir(exist_ok=True)
    
    # إضافة ملف README مبدئي جوه المادة
    readme_file = course_path / "README.md"
    if not readme_file.exists():
        with open(readme_file, "w") as f:
            f.write(f"# Course Workspace: {course_code}\nWelcome to your course environment.")
            
    print(f"[SUCCESS] Course workspace ready at: {course_path}")
    return str(course_path)

def list_courses():
    """استرجاع قائمة بكل المواد الموجودة في الـ Workspace"""
    courses_dir = WORKSPACE_DIR / "courses"
    if courses_dir.exists():
        return [f.name for f in courses_dir.iterdir() if f.is_dir()]
    return []

def get_course_path(course_code):
    """إرجاع المسار الكامل لمادة معينة"""
    return str(WORKSPACE_DIR / "courses" / course_code)

if __name__ == "__main__":
    print("Initializing Aegis Local Workspace...")
    init_workspace()
    
    # تجربة إنشاء مادتين للاختبار
    create_course_dir("CS301_AI")
    create_course_dir("CS302_Web")
    
    # طباعة المواد المتاحة
    print("\n--- Available Student Workspaces ---")
    print(list_courses())
    