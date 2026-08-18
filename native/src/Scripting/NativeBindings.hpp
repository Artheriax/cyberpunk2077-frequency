#ifndef FREQUENCY_NATIVE_BINDINGS_HPP
#define FREQUENCY_NATIVE_BINDINGS_HPP

namespace Frequency
{

/// Registers the `Frequency` scripting class and its functions with the
/// game's RTTI system.
class NativeBindings
{
public:
    /// Hooks into RED4ext's type-registration callbacks. Call once on load.
    static void ScheduleRegistration();

private:
    static void RegisterTypes();
    static void PostRegisterTypes();

    static void RegisterInfoFunctions();
    static void RegisterIoFunctions();
};

} // namespace Frequency

#endif // FREQUENCY_NATIVE_BINDINGS_HPP
