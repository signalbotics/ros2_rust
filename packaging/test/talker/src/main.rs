use rclrs::*;
use ros_env::std_msgs;
fn main() -> Result<(), RclrsError> {
    let mut executor = Context::default_from_env()?.create_basic_executor();
    let node = executor.create_node("talker_rs")?;
    let publisher = node.create_publisher::<std_msgs::msg::String>("chatter")?;
    let mut msg = std_msgs::msg::String::default();
    for i in 0..3 {
        msg.data = format!("hello {i}");
        publisher.publish(&msg)?;
        println!("published: {}", msg.data);
        std::thread::sleep(std::time::Duration::from_millis(200));
    }
    Ok(())
}
