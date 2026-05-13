using System;

namespace ContosoUniversity.Infrastructure
{
    /// <summary>
    /// Exception thrown by message queue operations
    /// </summary>
    public class MessageQueueException : Exception
    {
        public MessageQueueErrorCode MessageQueueErrorCode { get; }

        public MessageQueueException(string message) : base(message)
        {
            MessageQueueErrorCode = MessageQueueErrorCode.Generic;
        }

        public MessageQueueException(string message, Exception innerException) : base(message, innerException)
        {
            MessageQueueErrorCode = MessageQueueErrorCode.Generic;
        }

        public MessageQueueException(MessageQueueErrorCode errorCode, string message) : base(message)
        {
            MessageQueueErrorCode = errorCode;
        }
    }

    /// <summary>
    /// Message queue error codes
    /// </summary>
    public enum MessageQueueErrorCode
    {
        Generic = 0,
        IOTimeout = 1,
        QueueNotFound = 2,
        AccessDenied = 3,
        InvalidOperation = 4
    }

    /// <summary>
    /// Message queue access rights (for compatibility)
    /// </summary>
    [Flags]
    public enum MessageQueueAccessRights
    {
        FullControl = 983103,
        GenericRead = 131072,
        GenericWrite = 65536,
        SendMessage = 2,
        ReceiveMessage = 1,
        PeekMessage = 32,
        GetQueueProperties = 4,
        SetQueueProperties = 8,
        DeleteQueue = 65536,
        GetPermissions = 131072,
        ChangePermissions = 262144,
        TakeOwnership = 524288
    }
}