require "../../bacnet"
require "../message"

module BACnet
  module Message::Base
    property message : Message
    forward_missing_to @message

    abstract def data_link
  end
end
