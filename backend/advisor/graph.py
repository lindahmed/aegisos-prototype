from typing import TypedDict

from langgraph.graph import END, START, StateGraph

from .llm import ask_gemini


ALLOWED_INTENTS = {
    "academic_audit",
    "semester_planning",
    "career_guidance",
    "what_if_simulation",
    "general",
}

LANGUAGE_NAMES = {
    "english": "English",
    "arabic": "Arabic",
}


class AdvisorState(TypedDict, total=False):
    message: str
    intent: str
    response: str
    history: list[dict[str, str]]
    student: dict[str, object]
    context: dict[str, object]
    language: str


def _language_name(state: AdvisorState) -> str:
    return LANGUAGE_NAMES.get(state.get("language", "english"), "English")


def format_history(state: AdvisorState) -> str:
    history = state.get("history", [])
    if not history:
        return "No previous conversation."

    lines = []
    for message in history[-10:]:
        role = message["role"].capitalize()
        content = message["content"]
        lines.append(f"{role}: {content}")

    return "\n".join(lines)


def format_student(state: AdvisorState) -> str:
    student = state.get("student", {})
    courses = student.get("courses", [])
    course_text = ", ".join(str(course) for course in courses) or "None listed"

    return (
        f"Student ID: {student.get('student_id', 'Unknown')}\n"
        f"Name: {student.get('name', 'Unknown')}\n"
        f"Major: {student.get('major', 'Unknown')}\n"
        f"Year: {student.get('year', 'Unknown')}\n"
        f"GPA: {student.get('gpa', 'Unknown')}\n"
        f"Currently enrolled courses: {course_text}"
    )


def format_context(state: AdvisorState) -> str:
    context = state.get("context", {})
    if not context or context.get("twin") is None:
        return "No detailed academic progress context is available for this student."

    lines: list[str] = [
        f"Semester: {context.get('semester', 'Unknown')}",
        f"Current week: {context.get('current_week', 'Unknown')}",
        f"Overall academic health: {context.get('overall_academic_health', 'Unknown')}/100",
    ]

    for course in context.get("courses", []):
        metrics = course.get("metrics", {})
        lines.append(
            f"\nCourse: {course.get('course_name')} (risk: {course.get('risk_level', 'none')})"
        )
        lines.append(f"  - Health: {metrics.get('course_health', 'n/a')}/100, trend: {metrics.get('trend', 'n/a')}")
        lines.append(f"  - Weighted grade posted: {metrics.get('weighted_grade', 'n/a')}")
        lines.append(f"  - Assignment avg: {metrics.get('assignment_average', 'n/a')}, Lab avg: {metrics.get('lab_average', 'n/a')}, Exam: {metrics.get('exam_percentage', 'n/a')}")
        lines.append(f"  - Lecture completion: {metrics.get('lecture_completion', 'n/a')}%")
        if course.get("risks"):
            lines.append(f"  - Active risks: {'; '.join(risk.get('message', '') for risk in course['risks'])}")
        if course.get("unstudied_lectures"):
            lines.append(f"  - Unstudied lectures: {', '.join(str(n) for n in course['unstudied_lectures'])}")

    interventions = context.get("recent_interventions", [])
    if interventions:
        lines.append("\nRecent interventions:")
        for intervention in interventions[:5]:
            lines.append(
                f"  - Week {intervention.get('week_number')}: {intervention.get('message')} "
                f"(status: {intervention.get('status')})"
            )

    return "\n".join(lines)


def format_knowledge(state: AdvisorState) -> str:
    context = state.get("context", {})
    lines: list[str] = []

    programme = context.get("programme_progress")
    if programme:
        lines.append(
            f"Programme: {programme.get('programme_name')} "
            f"({programme.get('completed_credits')}/{programme.get('total_credits_required')} credits)."
        )
        lines.append(f"Completed courses: {', '.join(programme.get('completed_courses', [])) or 'None recorded'}.")
        lines.append(f"Registered this semester: {', '.join(programme.get('registered_courses', [])) or 'None recorded'}.")
        lines.append(f"Remaining required courses: {', '.join(programme.get('remaining_required_courses', [])) or 'None'}.")
    else:
        lines.append("No programme progress data is available.")

    eligibility = context.get("course_eligibility")
    if eligibility:
        lines.append(
            f"\nEligibility for {eligibility.get('course_code')} "
            f"({eligibility.get('course_title')}): {'Eligible' if eligibility.get('eligible') else 'Not eligible'}. "
            f"{eligibility.get('reason')}"
        )
        if eligibility.get("satisfied_prerequisites"):
            codes = ', '.join(p['course_code'] for p in eligibility['satisfied_prerequisites'])
            lines.append(f"  Satisfied prerequisites: {codes}.")
        if eligibility.get("in_progress_prerequisites"):
            codes = ', '.join(p['course_code'] for p in eligibility['in_progress_prerequisites'])
            lines.append(f"  In-progress prerequisites: {codes}.")
        if eligibility.get("missing_prerequisites"):
            codes = ', '.join(p['course_code'] for p in eligibility['missing_prerequisites'])
            lines.append(f"  Missing prerequisites: {codes}.")

    recommended = context.get("recommended_next_courses")
    if recommended:
        codes = ', '.join(r['course_code'] for r in recommended)
        lines.append(f"\nRecommended next courses (all prerequisites satisfied): {codes}.")

    return "\n".join(lines)


def classify_request(state: AdvisorState) -> AdvisorState:
    prompt = f"""
You are the request classifier for AegisOS Advisor AI.

Classify the student's latest message into exactly one of these intents:

academic_audit
- Completed courses, remaining courses, credits, degree progress, or graduation requirements.

semester_planning
- Choosing courses or planning the next semester.

career_guidance
- Jobs, skills, internships, career paths, or employment.

what_if_simulation
- The effect of a possible future event or academic decision.

general
- Greetings, unclear messages, or anything outside the previous categories.

Student profile:
{format_student(state)}

Previous conversation:
{format_history(state)}

Latest student message:
{state['message']}

Respond in {_language_name(state)}.
Return only the intent name. Do not include an explanation.
"""

    intent = ask_gemini(prompt).strip().lower()
    if intent not in ALLOWED_INTENTS:
        intent = "general"

    return {"intent": intent}


def route_request(state: AdvisorState) -> str:
    return state["intent"]


def _system_persona(intent: str) -> str:
    personas = {
        "academic_audit": "You are the Academic Audit specialist inside AegisOS Advisor AI.",
        "semester_planning": "You are the Semester Planning specialist inside AegisOS Advisor AI.",
        "career_guidance": "You are the Career Guidance specialist inside AegisOS Advisor AI.",
        "what_if_simulation": "You are the What-if Simulation specialist inside AegisOS Advisor AI.",
        "general": "You are Advisor AI inside AegisOS, an academic advising assistant.",
    }
    return personas.get(intent, personas["general"])


def _answer_guidelines(intent: str) -> str:
    guidelines = {
        "academic_audit": """
Use the detailed academic context and knowledge graph below to answer as fully as possible.
The knowledge graph contains programme requirements, completed courses, registered courses, and prerequisites.
You MUST answer directly from these facts. Do NOT tell the student to ask a human advisor, check a portal, read a catalog, or visit an office.
If a specific fact is missing, say exactly what is missing and still answer with what you know.
Do not invent completed courses, earned credits, prerequisites, curriculum rules, or graduation requirements.
""",
        "semester_planning": """
Use the student's actual programme rules, prerequisites, current courses, grades, and risks from the context below to recommend a plan.
You MUST answer directly from these facts. Do NOT tell the student to ask a human advisor, check a portal, read a catalog, or visit an office.
If prerequisites, credit limits, or registration rules are unknown, say so and still give a practical plan based on the known data.
Do not invent prerequisites or university rules.
""",
        "career_guidance": """
Give practical career guidance appropriate for this university student using their major, year, GPA, and current courses from the context.
You may suggest concrete next steps such as skills to build, project ideas, or internship timing, but do not invent specific job openings or guaranteed outcomes.
Do not redirect the student to a third party unless the question explicitly requires one.
""",
        "what_if_simulation": """
Explain the likely effect of the scenario using the student's actual current grades, weights, and programme rules from the context.
Do not invent university rules or guarantee an outcome.
Clearly separate what follows from the known profile from what depends on missing prerequisites, regulations, grades, or curriculum data.
""",
        "general": """
Respond briefly and helpfully. You can help with academic audits, semester planning, career guidance, and what-if simulations.
Use the academic context below when relevant.
Do not invent university rules or student information.
""",
    }
    return guidelines.get(intent, guidelines["general"])


def _generate_response(state: AdvisorState, intent: str) -> AdvisorState:
    prompt = f"""
{_system_persona(intent)}

Known student profile:
{format_student(state)}

Programme rules, prerequisites, and eligibility (authoritative knowledge graph):
{format_knowledge(state)}

Detailed semester progress context (courses, grades, risks, interventions):
{format_context(state)}

Recent conversation:
{format_history(state)}

Student question:
{state['message']}

{_answer_guidelines(intent)}

Respond in {_language_name(state)}.
Keep the answer concise, practical, and self-contained.
"""
    return {"response": ask_gemini(prompt)}


def academic_audit(state: AdvisorState) -> AdvisorState:
    return _generate_response(state, "academic_audit")


def semester_planning(state: AdvisorState) -> AdvisorState:
    return _generate_response(state, "semester_planning")


def career_guidance(state: AdvisorState) -> AdvisorState:
    return _generate_response(state, "career_guidance")


def what_if_simulation(state: AdvisorState) -> AdvisorState:
    return _generate_response(state, "what_if_simulation")


def general_response(state: AdvisorState) -> AdvisorState:
    return _generate_response(state, "general")


graph_builder = StateGraph(AdvisorState)
graph_builder.add_node("classify_request", classify_request)
graph_builder.add_node("academic_audit", academic_audit)
graph_builder.add_node("semester_planning", semester_planning)
graph_builder.add_node("career_guidance", career_guidance)
graph_builder.add_node("what_if_simulation", what_if_simulation)
graph_builder.add_node("general", general_response)

graph_builder.add_edge(START, "classify_request")
graph_builder.add_conditional_edges(
    "classify_request",
    route_request,
    {
        "academic_audit": "academic_audit",
        "semester_planning": "semester_planning",
        "career_guidance": "career_guidance",
        "what_if_simulation": "what_if_simulation",
        "general": "general",
    },
)
graph_builder.add_edge("academic_audit", END)
graph_builder.add_edge("semester_planning", END)
graph_builder.add_edge("career_guidance", END)
graph_builder.add_edge("what_if_simulation", END)
graph_builder.add_edge("general", END)

advisor_graph = graph_builder.compile()
