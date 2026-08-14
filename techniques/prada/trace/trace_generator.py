from math import log2
import os
import sys
import argparse
import random
from typing import List
from utils.trace import Trace

ROW_BITS = 16
BANK_BITS = 2
BANK_GROUP_BITS = 3
RANK_BITS = 0
CHANNEL_BITS = 0
COLUMN_BITS = 6
CACHE_BLOCK_SIZE = 64  # in bytes
TX_BITS = int(log2(CACHE_BLOCK_SIZE))

ROW_MASK = (1 << ROW_BITS) - 1
BANK_MASK = (1 << BANK_BITS) - 1
BANK_GROUP_MASK = (1 << BANK_GROUP_BITS) - 1
RANK_MASK = (1 << RANK_BITS) - 1
CHANNEL_MASK = (1 << CHANNEL_BITS) - 1
COLUMN_MASK = (1 << COLUMN_BITS) - 1

def get_physical_address(channel: int, rank: int, bank_group: int, bank: int, row: int, column: int) -> int:
    """
    Convert channel, bank, bank group, row, rank, and column to a physical address by applying the RoBaRaCoCh mapping
    for a DDR5_16Gb_x8 which has 1 channel and 2 ranks.
    
    Args:
        channel (int): The channel number.
        bank (int): The bank number.
        bank_group (int): The bank group number.
        row (int): The row number.
        rank (int): The rank number.
        column (int): The column number.

    Returns:
        int: The physical address.
    """
    addr = 0 

    if (channel != 0):
        raise ValueError("Channel should be 0 for this mapping.")

    # The mapping is as follows:
    addr |= (row & ROW_MASK)

    addr <<= BANK_BITS
    addr |= (bank & BANK_MASK)

    addr <<= BANK_GROUP_BITS
    addr |= (bank_group & BANK_GROUP_MASK)

    addr <<= RANK_BITS
    addr |= (rank & RANK_MASK)

    addr <<= COLUMN_BITS
    addr |= (column & COLUMN_MASK)

    addr <<= CHANNEL_BITS
    addr |= (channel & CHANNEL_MASK)

    # Internal prefetch width (2^4) and number of chips (2^2) for DDR5_16Gb_x8 and channel width of 64 bits (2^3)
    addr <<= TX_BITS

    return addr


def gen_base_two_ip(set_size: int) -> Trace:
    """
    Generates a baseline memory trace with only read and write requests.
    Args:
        set_size (int): The operating set size in MB.
    Returns:
        Trace: A Trace object containing the generated memory requests.
    """
    trace = Trace()

    set_size_bytes = set_size * 1024 * 1024
    num_cache_blocks = set_size_bytes // CACHE_BLOCK_SIZE

    a_addr_range = {"start": 0, "end": set_size_bytes - CACHE_BLOCK_SIZE}
    b_addr_range = {"start": set_size_bytes, "end": 2 * set_size_bytes - CACHE_BLOCK_SIZE}
    dest_addr_range = {"start": 2 * set_size_bytes, "end": 3 * set_size_bytes - CACHE_BLOCK_SIZE}

    for i in range(num_cache_blocks):
        # Load from A in a serial order
        srcA_addr = a_addr_range["start"] + i * CACHE_BLOCK_SIZE
        trace.add_ldst_entry(bubbles=0, load_addr=srcA_addr, store_addr=-1)

        # Load from B
        srcB_addr = b_addr_range["start"] + i * CACHE_BLOCK_SIZE
        trace.add_ldst_entry(bubbles=0, load_addr=srcB_addr, store_addr=-1)

        # Store to dest
        dest_addr = dest_addr_range["start"] + i * CACHE_BLOCK_SIZE
        trace.add_ldst_entry(bubbles=1, load_addr=dest_addr, store_addr=dest_addr)

    return trace


def gen_base_one_ip(set_size: int) -> Trace:
    """
    Generates a baseline memory trace with only read and write requests.
    Args:
        set_size (int): The operating set size in MB.
    Returns:
        Trace: A Trace object containing the generated memory requests.
    """
    trace = Trace()

    set_size_bytes = set_size * 1024 * 1024
    num_cache_blocks = set_size_bytes // CACHE_BLOCK_SIZE

    a_addr_range = {"start": 0, "end": set_size_bytes - CACHE_BLOCK_SIZE}
    dest_addr_range = {"start": set_size_bytes, "end": 2 * set_size_bytes - CACHE_BLOCK_SIZE}

    for i in range(num_cache_blocks):
        # Load from A in a serial order
        srcA_addr = a_addr_range["start"] + i * CACHE_BLOCK_SIZE
        trace.add_ldst_entry(bubbles=0, load_addr=srcA_addr, store_addr=-1)

        # Store to dest
        dest_addr = dest_addr_range["start"] + i * CACHE_BLOCK_SIZE
        trace.add_ldst_entry(bubbles=1, load_addr=dest_addr, store_addr=dest_addr)

    return trace


def gen_pum_two_ip(set_size: int, num_bankgroups: int, num_banks: int) -> Trace:
    """
    Generates a memory trace of 2-input PuM requests.
    Args:
        set_size (int): The operating set size in MB.
        num_bankgroups (int): Bank groups the operation is parallelized across.
        num_banks (int): Banks per bank group the operation is parallelized across.
    Returns:
        Trace: A Trace object containing the generated memory requests.
    """
    print("Generating PuM 2-input trace...")

    trace = Trace()

    set_size_bytes = set_size * 1024 * 1024
    row_size_bytes = 2 ** (COLUMN_BITS + TX_BITS)

    num_ranks = 2 ** RANK_BITS

    num_flat_banks = num_ranks * num_bankgroups * num_banks

    # set_size is divided across the banks and each op is row-sized
    num_ops_per_bank = set_size_bytes // (row_size_bytes * num_flat_banks)

    a_row_addr_range = {"start": 0, "end": num_ops_per_bank - 1}
    b_row_addr_range = {"start": num_ops_per_bank, "end": 2 * num_ops_per_bank - 1}
    dest_row_addr_range = {"start": 2 * num_ops_per_bank, "end": 3 * num_ops_per_bank - 1}

    for op in range(num_ops_per_bank):
        for bank in range(num_banks):
            for bankgroup in range(num_bankgroups):
                for rank in range(num_ranks):

                    a_row_addr = a_row_addr_range["start"] + op
                    b_row_addr = b_row_addr_range["start"] + op
                    dest_row_addr = dest_row_addr_range["start"] + op
                    
                    a_addr = get_physical_address(0, rank, bankgroup, bank, a_row_addr, 0)
                    b_addr = get_physical_address(0, rank, bankgroup, bank, b_row_addr, 0)
                    dest_addr = get_physical_address(0, rank, bankgroup, bank, dest_row_addr, 0)

                    trace.add_2input_pum_entry(bubbles=0, source1_addr=a_addr, source2_addr=b_addr, dest_addr=dest_addr)

    return trace


def gen_pum_one_ip(set_size: int, num_bankgroups: int, num_banks: int) -> Trace:
    """
    Generates a memory trace of 1-input PuM requests.
    Args:
        set_size (int): The operating set size in MB.
        num_bankgroups (int): Bank groups the operation is parallelized across.
        num_banks (int): Banks per bank group the operation is parallelized across.
    Returns:
        Trace: A Trace object containing the generated memory requests.
    """
    trace = Trace()

    set_size_bytes = set_size * 1024 * 1024
    row_size_bytes = 2 ** (COLUMN_BITS + TX_BITS)

    num_ranks = 2 ** RANK_BITS

    num_flat_banks = num_ranks * num_bankgroups * num_banks

    # set_size is divided across the banks and each op is row-sized
    num_ops_per_bank = set_size_bytes // (row_size_bytes * num_flat_banks)

    a_row_addr_range = {"start": 0, "end": num_ops_per_bank - 1}
    dest_row_addr_range = {"start": num_ops_per_bank, "end": 2 * num_ops_per_bank - 1}

    for op in range(num_ops_per_bank):
        for bank in range(num_banks):
            for bankgroup in range(num_bankgroups):
                for rank in range(num_ranks):
                    a_row_addr = a_row_addr_range["start"] + op
                    dest_row_addr = dest_row_addr_range["start"] + op
                    
                    a_addr = get_physical_address(0, rank, bankgroup, bank, a_row_addr, 0)
                    dest_addr = get_physical_address(0, rank, bankgroup, bank, dest_row_addr, 0)

                    trace.add_1input_pum_entry(bubbles=0, source1_addr=a_addr, dest_addr=dest_addr)
                    
    return trace


def generate_trace(trace_type:str, set_size:int, trace_file: str, banks: str = "full"):
    """
    Main function to generate a memory trace based on the specified type and size.

    Args:
        trace_type (str): The type of trace to generate. Options include:
                          - "base": Baseline with only Reads and Writes.
                          - "pum": Operations with PuM requests.
        set_size (in MB): Operating set in MB
        trace_file (str): The file path where the generated trace will be saved.
        banks (str): PuM bank parallelism -- "full" (all banks, the *_32M case) or
                     "single" (one bank, the *_1b case). Ignored for base traces.

    Returns:
        None: The function generates a trace file at the specified path.

    Raises:
        ValueError: If an invalid trace type is specified.
    """
    if banks == "full":
        num_bankgroups = 2 ** BANK_GROUP_BITS
        num_banks = 2 ** BANK_BITS
    elif banks == "single":
        num_bankgroups = 1
        num_banks = 1
    else:
        raise ValueError(f"invalid banks '{banks}' (expected 'full' or 'single')")

    if trace_type == "base_2ip":
        trace = gen_base_two_ip(set_size)
    elif trace_type == "base_1ip":
        trace = gen_base_one_ip(set_size)
    elif trace_type == "pum_2ip":
        trace = gen_pum_two_ip(set_size, num_bankgroups, num_banks)
    elif trace_type == "pum_1ip":
        trace = gen_pum_one_ip(set_size, num_bankgroups, num_banks)
    else:
        print("Invalid trace type specified. Exiting.")
        sys.exit(1)

    trace_list = trace.get_all_entries()

    if os.path.exists(trace_file):
        os.remove(trace_file)
    
    # Write trace entries to a file
    with open(trace_file, "w") as f:
        for trace_entry in trace_list:
            f.write(str(trace_entry) + "\n")

    return


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Run the RC Benchmarks.")

    parser.add_argument(
        "--trace-file",
        type=str,
        default="rc.trace",
        help="Path to the trace file to be generated.",
    )
    parser.add_argument(
        "--trace-type",
        type=str,
        help="Type of trace to generate (default: base_2ip).",
        default="base_2ip",
        choices=["base_2ip", "base_1ip", "pum_2ip", "pum_1ip"],
    )
    parser.add_argument(
        "--set-size",
        type=int,
        help="Set size in MB (default: 32).",
        default=32,
    )
    parser.add_argument(
        "--banks",
        type=str,
        default="full",
        choices=["full", "single"],
        help="PuM bank parallelism: 'full' (all banks, the *_32M case) or 'single' "
             "(one bank, the *_1b case). Ignored for base traces (default: full).",
    )

    args = parser.parse_args()

    generate_trace(args.trace_type, args.set_size, args.trace_file, args.banks)