import random

class TraceEntry:
    """
    A class to represent a trace entry with information about bubbles, load address, and store address.

    Attributes:
        bubbles (int): The number of bubbles (idle cycles) in the trace entry.
        type (int): Type of operation (0 for LD/ST, 1 for 2 input PuM, and 2 for 1 input PuM).
        load_addr (int): The memory address for a load operation.
        store_addr (int): The memory address for a store operation.
        source1_addr (int): The memory address for the first source operand in a PuM operation.
        source2_addr (int): The memory address for the second source operand in a PuM operation.
        dest_addr (int): The memory address for the destination operand in a PuM operation.

    Methods:
        __repr__(): Returns a string representation of the TraceEntry object in the format "bubbles load_addr store_addr".
    """
    def __init__(self, bubbles: int, type: int, load_addr: int, store_addr: int, source1_addr: int, source2_addr: int, dest_addr: int):
        self.bubbles = bubbles
        self.type = type
        self.load_addr = load_addr
        self.store_addr = store_addr
        self.source1_addr = source1_addr
        self.source2_addr = source2_addr
        self.dest_addr = dest_addr

    def __repr__(self) -> str:
        return "{} {} {} {} {} {} {}".format(self.bubbles, self.type, self.load_addr, self.store_addr, self.source1_addr, self.source2_addr, self.dest_addr)


class Trace:
    """
    Trace class for managing trace entries.

    The Trace class provides functionality to add, randomly insert, and retrieve trace entries.
    Each trace entry contains information about timestamp, bubbles, load address, and store address.

    Methods:
        __init__():
            Initializes an empty trace list.

        add_entry(bubbles: int, load_addr: int, store_addr: int):
            Adds a trace entry to the trace.

        randomly_insert_entry(bubbles: int, load_addr: int, store_addr: int):
            Inserts a trace entry into the trace at a randomly chosen location.

        get_all_entries():
            Retrieves all trace entries as a list.
    """
    def __init__(self):
        self.trace = []

    def add_ldst_entry(self, bubbles: int, load_addr: int, store_addr: int):
        """
        Adds a trace entry to the trace.

        Args:
            bubbles (int): The number of bubbles in the trace entry.
            load_addr (int): The load address in the trace entry.
            store_addr (int): The store address in the trace entry.
        """      
        self.trace.append(TraceEntry(bubbles, 0, load_addr, store_addr, -1, -1, -1))

    def add_2input_pum_entry(self, bubbles: int, source1_addr: int, source2_addr: int, dest_addr: int):
        """
        Adds a 2-input PuM trace entry to the trace.

        Args:
            bubbles (int): The number of bubbles in the trace entry.
            source1_addr (int): The first source address in the trace entry.
            source2_addr (int): The second source address in the trace entry.
            dest_addr (int): The destination address in the trace entry.
        """      
        self.trace.append(TraceEntry(bubbles, 1, -1, -1, source1_addr, source2_addr, dest_addr))

    def add_1input_pum_entry(self, bubbles: int, source1_addr: int, dest_addr: int):
        """
        Adds a 1-input PuM trace entry to the trace.

        Args:
            bubbles (int): The number of bubbles in the trace entry.
            source1_addr (int): The source address in the trace entry.
            dest_addr (int): The destination address in the trace entry.
        """      
        self.trace.append(TraceEntry(bubbles, 2, -1, -1, source1_addr, -1, dest_addr))

    def get_all_entries(self):
        """
        Returns all entries in the trace.

        Returns:
            list: A list of all TraceEntry objects in the trace.
        """       
        return self.trace
