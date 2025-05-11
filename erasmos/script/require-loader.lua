import solara
import requests
import json
import hashlib
from typing import Dict, Optional

# Replace with your actual server address and API key
SERVER_URL = "http://localhost:4566"
API_KEY = "a35d863f-865e-4669-8c3a-724c9f0749d3"

# Global cache for required modules, analogous to cachedRequires in the Lua script
_cached_requires: Dict[str, Optional[object]] = {}

def _fetch_file(url: str) -> Optional[str]:
    """
    Fetches the content of a file from the server.  Handles potential errors.
    """
    try:
        response = requests.post(
            f"{SERVER_URL}/getFile",
            headers={
                "Content-Type": "application/json",
                "Authorization": API_KEY,
            },
            json={"paths": [url, ""]},  #  Mimic the Lua script's path structure
        )
        response.raise_for_status()  # Raise an exception for bad status codes
        return response.text
    except requests.exceptions.RequestException as e:
        print(f"[ERROR] Failed to fetch {url}: {e}")
        return None

def _load_and_execute_script(script_content: str, script_name: str) -> Optional[object]:
    """
    Loads and executes Python code (equivalent to Lua's loadstring).
    Handles potential syntax errors and execution errors.
    """
    try:
        #  In Python, we use exec() for dynamic code execution, similar to loadstring() in Lua
        #  We create a local namespace to mimic the behavior of a script environment.
        local_namespace = {}
        exec(script_content, local_namespace)

        #  Check if the script defined a main function (common pattern)
        if "main" in local_namespace:
            return local_namespace["main"]()  # Execute the main function
        elif "__getattr__" in local_namespace: #Check for a class.
            return local_namespace
        elif len(local_namespace) > 0:
            # Return the first function or object defined in the script.
            for key, value in local_namespace.items():
                if callable(value) or not key.startswith("__"): # Exclude private attributes
                    return value
        else:
            return None # Script did not define anything to return
    except SyntaxError as e:
        print(f"[ERROR] Syntax error in {script_name}: {e}")
        return None
    except Exception as e:
        print(f"[ERROR] Error executing {script_name}: {e}")
        return None

def custom_require(url: str) -> Optional[object]:
    """
    Custom require function to fetch and execute scripts from a server,
    analogous to the customRequire function in the Lua script.
    """
    if not isinstance(url, str):
        raise TypeError("url must be a string")

    #  Use url as filename, strip any leading ../
    filename = url.split('/')[-1]

    if filename not in _cached_requires:
        script_content = _fetch_file(url)
        if script_content is None:
            return None  #  Return None on failure, consistent with error handling

        #  Check file extension.  Crucial for security.
        if filename.endswith(".lua"):
            print("[WARN] .lua file extension found, this is unusual, was this supposed to be python?")

        elif filename.endswith(".py"):
          _cached_requires[filename] = _load_and_execute_script(script_content, filename)
        elif filename.endswith(".json"):
            try:
                _cached_requires[filename] = json.loads(script_content)
            except json.JSONDecodeError as e:
                print(f"[ERROR] Invalid JSON in {filename}: {e}")
                return None
        else:
            _cached_requires[filename] = script_content # treat as data
    return _cached_requires[filename]


def shared_require(url: str) -> Optional[object]:
    """
    Shared require function to cache and reuse required modules,
    analogous to the customRequireShared function in the Lua script.
    """
    filename = url.split('/')[-1] # extract filename
    if filename not in _cached_requires:
        _cached_requires[filename] = custom_require(url)
    return _cached_requires[filename]



@solara.component
def ScriptLoader():
    """
    Solara component to demonstrate the custom_require and shared_require functions.
    """
    status, set_status = solara.use_state("Loading...")
    loaded_data, set_loaded_data = solara.use_state[object](None)
    error_message, set_error_message = solara.use_state[str](None)

    def load_script():
        set_status("Loading script...")
        try:
            #  Example usage:  Load a Python "module" (simulated script)
            #  In a real application, you'd replace this with a path to your server.
            #  For this example, we'll define a simple Python script as a string.
            #
            #  Important:  For security, you should NEVER load and execute
            #  arbitrary code from an untrusted source.  This is just for
            #  demonstration purposes.  In a real application, the "scripts"
            #  would be carefully controlled modules within your project.

            # Simulate a simple python module.
            simulated_module_code = """
def hello():
    return "Hello from the simulated module!"

class MyClass:
    def __init__(self, name):
        self.name = name

    def get_name(self):
        return f"My name is {self.name}"

def main():
  return "This is the main function"
            """
            # Create a temporary file
            with open("simulated_module.py", "w") as f:
                f.write(simulated_module_code)
            #  Use a relative URL for demonstration
            #loaded_module = custom_require("simulated_module.py") # This would be the correct way.
            loaded_module = custom_require("./simulated_module.py")
            if loaded_module:
                if callable(loaded_module):
                  set_loaded_data(loaded_module()) # Call the function if it is callable.
                elif hasattr(loaded_module, "__getattr__"):
                   set_loaded_data(loaded_module)
                else:
                  set_loaded_data(loaded_module)
                set_status("Script loaded successfully.")
            else:
                set_error_message("Failed to load script.")
                set_status("Error")

            # Example of loading JSON data
            json_data = shared_require("./data.json")

            if json_data:
                print(f"Loaded JSON data: {json_data}")
            else:
                print("Failed to load JSON data.")
        except Exception as e:
            set_error_message(f"An error occurred: {e}")
            set_status("Error")

    # Simulate a json file.
    simulated_json_data = """
    {
        "name": "John Doe",
        "age": 30,
        "city": "New York"
    }
    """

    with open("data.json", "w") as f:
        f.write(simulated_json_data)
    solara.Button("Load Script", on_click=load_script)

    solara.Text(status)
    if loaded_data:
        if callable(loaded_data):
          solara.Text(f"Result: {loaded_data()}")
        elif isinstance(loaded_data, type): #check for class
            obj = loaded_data("Test Instance")
            solara.Text(f"Result: {obj.get_name()}")
        else:
          solara.Text(f"Result: {loaded_data}")
    if error_message:
        solara.Error(error_message)
