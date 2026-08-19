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


class AdvisorState(TypedDict, total=False):
    message: str
    intent: str
    response: str
    history: list[dict[str, str]]
    student: dict[str, object]


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

Return only the intent name. Do not include an explanation.
"""

    intent = ask_gemini(prompt).strip().lower()
    if intent not in ALLOWED_INTENTS:
        intent = "general"

    return {"intent": intent}


def route_request(state: AdvisorState) -> str:
    return state["intent"]


def academic_audit(state: AdvisorState) -> AdvisorState:
    prompt = f"""
You are the Academic Audit specialist inside AegisOS Advisor AI.

Known student profile:
{format_student(state)}

Recent conversation:
{format_history(state)}

Student question:
{state['message']}

Use the known profile when relevant. The listed courses are current enrollments, not proof of completed courses.
Do not invent completed courses, earned credits, prerequisites, curriculum rules, or graduation requirements.
If the answer needs information that is not present, say exactly what information is missing.
Keep the answer concise and practical.
"""
    return {"response": ask_gemini(prompt)}


def semester_planning(state: AdvisorState) -> AdvisorState:
    prompt = f"""
You are the Semester Planning specialist inside AegisOS Advisor AI.

Known student profile:
{format_student(state)}

Recent conversation:
{format_history(state)}

Student question:
{state['message']}

Use the student's actual current courses and profile when relevant.
Do not invent prerequisites, completed courses, credit limits, or university rules.
If important curriculum information is missing, make that limitation explicit before recommending a plan.
Keep the recommendation simple and practical.
"""
    return {"response": ask_gemini(prompt)}


def career_guidance(state: AdvisorState) -> AdvisorState:
    prompt = f"""
You are the Career Guidance specialist inside AegisOS Advisor AI.

Known student profile:
{format_student(state)}

Recent conversation:
{format_history(state)}

Student question:
{state['message']}

Give practical career guidance appropriate for this university student.
You may use the major, year, GPA, and current courses as context, but do not invent experience or skills that are not shown.
Keep the answer concise and actionable.
"""
    return {"response": ask_gemini(prompt)}


def what_if_simulation(state: AdvisorState) -> AdvisorState:
    prompt = f"""
You are the What-if Simulation specialist inside AegisOS Advisor AI.

Known student profile:
{format_student(state)}

Recent conversation:
{format_history(state)}

Student scenario:
{state['message']}

Explain the likely effect of the scenario.
Do not invent university rules or guarantee an outcome.
Clearly separate what follows from the known profile from what depends on missing prerequisites, regulations, grades, or curriculum data.
Keep the answer concise and practical.
"""
    return {"response": ask_gemini(prompt)}


def general_response(state: AdvisorState) -> AdvisorState:
    prompt = f"""
You are Advisor AI inside AegisOS, an academic advising assistant.

Known student profile:
{format_student(state)}

Recent conversation:
{format_history(state)}

Student message:
{state['message']}

Respond briefly. You can help with academic audits, semester planning, career guidance, and what-if simulations.
Do not invent university rules or student information.
"""
    return {"response": ask_gemini(prompt)}


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
