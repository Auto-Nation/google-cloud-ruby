# Copyright 2017 Google Inc. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


require "google/cloud/logging/logger"

module Google
  module Cloud
    module Debugger
      ##
      # Rack Middleware implementation that supports Stackdriver Debugger Agent
      # in Rack-based Ruby frameworks. It instantiates a new debugger agent if
      # one isn't given already. It helps optimize Debugger Agent Tracer
      # performance by suspend and resume tracer between each request.
      class Middleware
        ##
        # Create a new Debugger Middleware.
        #
        # @param [Rack Application] app Rack application
        # @param [Google::Cloud::Debugger::Project] debugger A debugger to be
        #   used by this middleware. If not given, will construct a new one
        #   using the other parameters.
        # @param [Hash] *kwargs Hash of configuration settings. Used for
        #   backward API compatibility. See the [Configuration
        #   Guide](https://googlecloudplatform.github.io/google-cloud-ruby/#/docs/stackdriver/guides/instrumentation_configuration)
        #   for the prefered way to set configuration parameters.
        #
        # @return [Google::Cloud::Debugger::Middleware] A new
        #   Google::Cloud::Debugger::Middleware instance
        #
        def initialize app, debugger: nil, **kwargs
          @app = app

          load_config kwargs

          @debugger = debugger ||
                      Debugger.new(project: configuration.project_id,
                                   keyfile: configuration.keyfile,
                                   module_name: configuration.module_name,
                                   module_version: configuration.module_version)

          # Immediately start the debugger agent
          @debugger.start
        end

        ##
        # Rack middleware entry point. In most Rack based frameworks, a request
        # is served by one thread. It enables/resume the debugger breakpoints
        # tracing and stops/pauses the tracing afterwards to help improve
        # debugger performance.
        #
        # @param [Hash] env Rack environment hash
        #
        # @return [Rack::Response] The response from downstream Rack app
        #
        def call env
          # Enable/resume breakpoints tracing
          @debugger.agent.tracer.start

          # Use Stackdriver Logger for debugger if available
          if env["rack.logger"].is_a? Google::Cloud::Logging::Logger
            @debugger.agent.logger = env["rack.logger"]
          end

          @app.call env
        ensure
          # Stop breakpoints tracing beyond this point
          @debugger.agent.tracer.disable_traces_for_thread
        end

        private

        ##
        # Consolidate configurations from various sources. Also set
        # instrumentation config parameters to default values if not set
        # already.
        #
        def load_config **kwargs
          configuration.project_id = kwargs[:project] ||
                                     kwargs[:project_id] ||
                                     configuration.project_id
          configuration.keyfile = kwargs[:keyfile] ||
                                  configuration.keyfile

          configuration.module_name = kwargs[:module_name] ||
                                      configuration.module_name
          configuration.module_version = kwargs[:module_version] ||
                                         configuration.module_version

          init_default_config
        end

        ##
        # Fallback to default configuration values if not defined already
        def init_default_config
          configuration.project_id ||= Cloud.configure.project_id ||
                                       Debugger::Project.default_project
          configuration.keyfile ||= Cloud.configure.keyfile

          configuration.module_name ||= Debugger::Project.default_module_name
          configuration.module_version ||=
            Debugger::Project.default_module_version
        end

        ##
        # @private Get Google::Cloud::Debugger.configure
        def configuration
          Google::Cloud::Debugger.configure
        end
      end
    end
  end
end
