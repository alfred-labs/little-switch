func nativeResponsesSearchResponse() -> String {
    #"""
    {
      "id": "resp_search",
      "output": [
        {
          "id": "fc_search",
          "type": "function_call",
          "status": "completed",
          "call_id": "call_search",
          "name": "web_search",
          "arguments": "{\"query\":\"Swift\"}"
        }
      ],
      "usage": {"input_tokens": 1, "output_tokens": 1, "total_tokens": 2}
    }
    """#
}

func nativeResponsesFinalResponse() -> String {
    #"""
    {
      "id": "resp_final",
      "output": [
        {
          "id": "msg_final",
          "type": "message",
          "status": "completed",
          "role": "assistant",
          "content": [
            {"type": "output_text", "text": "Done", "annotations": [], "logprobs": []}
          ]
        }
      ],
      "usage": {"input_tokens": 1, "output_tokens": 1, "total_tokens": 2}
    }
    """#
}
